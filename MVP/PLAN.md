# iRelay MVP — Implementation Plan

## iMessage Integration: The Options

There is **no direct Swift API** for iMessage. Apple doesn't provide one. Here are the real options:

### Sending Messages

| Approach | How | Pros | Cons |
|----------|-----|------|------|
| **NSAppleScript** (recommended) | In-process AppleScript, compile once, reuse | No subprocess spawn, ~50ms faster, handles text + files | Must dispatch off actor (not thread-safe) |
| osascript subprocess | Current approach | Simple | Process spawn overhead per message |
| IMCore private framework | Link `/System/Library/PrivateFrameworks/IMCore.framework` | Full features (typing, reactions, effects) | Requires SIP disabled, breaks across macOS versions |

### Receiving Messages

| Approach | How | Pros | Cons |
|----------|-----|------|------|
| **chat.db + FSEvents** (recommended) | GRDB reads + DispatchSource file watching | Event-driven, no busy polling, reliable schema | Needs Full Disk Access |
| chat.db polling | Query every N ms | Simpler | Wastes CPU, may miss messages between polls |
| IMCore notifications | NotificationCenter observers | Real-time | Requires SIP disabled |

### What OpenClaw Does

OpenClaw uses **neither** AppleScript nor chat.db directly. It delegates to an external tool called `imsg`:
- Spawns `imsg rpc` as a subprocess
- Talks JSON-RPC over stdin/stdout
- `imsg` internally uses AppleScript for sending and chat.db for receiving
- Clean separation — OpenClaw knows nothing about Messages.app internals

### Decision: Use IMsgCore (steipete/imsg)

After evaluating all options, we're going with **[steipete/imsg](https://github.com/steipete/imsg)**'s `IMsgCore` library target.

**What IMsgCore gives us for free:**
- **FSEvents-based message watching** — monitors chat.db + WAL + SHM files, returns `AsyncThrowingStream<Message, Error>`. Event-driven, not polling.
- **attributedBody parsing** — lightweight binary parser for NSTypedStream blobs (macOS Ventura+ moved message text here)
- **Schema detection** — adapts to chat.db schema changes across macOS versions
- **NSAppleScript sending** — compile once, reuse. Auto-fallback to osascript on auth errors. Handles text + file attachments.
- **Phone number normalization** — E.164 via PhoneNumberKit
- **URL balloon deduplication** — prevents duplicate processing when rich link previews write multiple rows
- **Reaction events** — tapback tracking
- **Attachment metadata** — filename, MIME type, size, path resolution with tilde expansion

**Package details:**
- Swift 6.0, macOS 14+, MIT license, 824 stars, actively maintained (last commit: March 2, 2026)
- `IMsgCore` is a standalone library target — we don't pull in the CLI
- Dependencies: SQLite.swift, PhoneNumberKit, ScriptingBridge.framework (system)

**Trade-off:** We'll carry SQLite.swift alongside GRDB (two SQLite wrappers). Acceptable — IMsgCore uses SQLite.swift for chat.db reads, GRDB handles our own storage. Clean separation by database.

**What we still build ourselves:**
- Channel protocol adapter (wrap IMsgCore's API into our `Channel` protocol)
- Multimodal content mapping (IMsgCore `Message` → our `InboundMessage`)
- Outbound media handling (write temp files, pass to IMsgCore's sender)
- Configuration (allowlist, debounce settings)

**Why not the other options:**
- **Build from scratch (Option A):** Would reimplement ~800 lines of IMsgCore's battle-tested code — attributedBody parsing alone is tricky
- **Spawn imsg CLI (Option C, OpenClaw's approach):** Adds a runtime dependency on an installed binary. We're Swift — depend on the library directly

---

## Implementation Plan

### Phase 1: Channel Protocol Refactor
**Goal**: Multimodal messages flow end-to-end

```
Day 1-2
├── ChannelKit
│   ├── Add ChannelCapabilities (OptionSet)
│   ├── Add ChannelLimits (struct with per-channel presets)
│   └── Add capabilities + limits to Channel protocol (with defaults)
│
├── Shared
│   ├── Add .video, .link, .compound to MessageContent
│   ├── Add textFallback computed property
│   ├── Add ContentBlock enum (text, image, toolUse, toolResult)
│   └── Refactor ChatMessage.content from String to [ContentBlock]
│
├── ProviderKit + ClaudeProvider
│   ├── Update CompletionOptions to accept [ContentBlock]
│   ├── Format image content blocks for Claude Vision API
│   └── Parse tool_use content blocks from streaming response
│
└── Services
    └── Update ServiceOrchestrator to check capabilities before delivery
```

**Tests**: ContentBlock round-trip encoding, capability checking, text fallback

---

### Phase 2: iMessage Full Channel (parallel with Phase 3, 4)
**Goal**: Bidirectional multimodal iMessage via IMsgCore

```
Day 3-5
├── Add IMsgCore dependency
│   ├── Add steipete/imsg to Package.swift (.upToNextMinor(from: "0.5.0"))
│   ├── IMessageChannel depends on IMsgCore + ChannelKit + Shared
│   └── Verify build with new dependency
│
├── Inbound (IMsgCore MessageWatcher)
│   ├── Create MessageWatcher with config (dbPath, debounce, batchLimit)
│   ├── Consume watcher.stream() → AsyncThrowingStream<Message, Error>
│   ├── Filter: skip is_from_me messages
│   ├── Map IMsgCore Message → InboundMessage
│   │   ├── message.text → .text(String)
│   │   ├── message.attachments → read file data → .image/.video/.file
│   │   ├── message with text + attachments → .compound([...])
│   │   └── message.sender → senderID, message.chatGUID → sessionKey
│   ├── Allowlist check before dispatching to handler
│   └── IMsgCore handles dedup, attributedBody, URL balloon filtering
│
├── Outbound (IMsgCore MessageSender)
│   ├── Create MessageSender with service config (iMessage/SMS/auto)
│   ├── Text: sender.send(text, to: recipient)
│   ├── Images/files: write Data to temp → sender.send(text, to:, file: path)
│   ├── Compound: send text first, then each attachment
│   └── Cleanup temp files after send
│
└── Configuration
    ├── Allowlist (who can message the bot)
    ├── dbPath override (default: ~/Library/Messages/chat.db)
    └── service preference (iMessage / SMS / auto)
```

**Tests**: IMsgCore Message → InboundMessage mapping, allowlist filtering, outbound content routing

---

### Phase 3: WhatsApp Media (parallel with Phase 2, 4)
**Goal**: Images, video, documents flow both ways

```
Day 3-4
├── Inbound media
│   ├── Parse webhook type field: image, video, document, audio
│   ├── Extract media ID from webhook payload
│   ├── GET /v21.0/{media-id} → get download URL
│   ├── Download media bytes
│   └── Build InboundMessage with appropriate MessageContent case
│
├── Outbound media
│   ├── POST /v21.0/{phone-number-id}/media (multipart upload)
│   ├── Send image: type "image", image: { id: media-id }
│   ├── Send document: type "document", document: { id, filename }
│   ├── Send video: type "video", video: { id: media-id }
│   └── Compound: send each part sequentially
│
└── Update capabilities + limits to .multimedia / .whatsapp
```

**Tests**: Webhook parsing for each media type, media upload mock

---

### Phase 4: Agent Spawner (parallel with Phase 2, 3)
**Goal**: Spawn Claude Code / Codex and stream output

```
Day 3-6
├── Package: AgentSpawner
│   ├── AgentType enum (claude, codex, custom)
│   ├── AgentSpawnConfig (workingDir, model, timeout, budget, allowedTools)
│   ├── AgentStreamEvent enum (text, toolUse, toolResult, progress, done, error)
│   │
│   ├── CLIBuilder
│   │   ├── Claude: claude -p --output-format stream-json --working-dir ...
│   │   ├── Codex: codex exec "prompt"
│   │   └── Custom: arbitrary executable + args
│   │
│   ├── StreamParser
│   │   ├── Claude: parse JSON lines → AgentStreamEvent
│   │   ├── Codex: parse text/JSON output → AgentStreamEvent
│   │   └── Line-by-line async reading from Pipe
│   │
│   ├── AgentSpawner actor
│   │   ├── spawn(prompt, config, attachments) → AsyncThrowingStream
│   │   ├── cancel(sessionID)
│   │   ├── active sessions tracking
│   │   ├── Timeout enforcement (Task.sleep race)
│   │   └── Process tree cleanup (SIGTERM → grace → SIGKILL)
│   │
│   └── ProgressCoalescer
│       ├── Buffer rapid events
│       ├── Emit meaningful updates at ~2s intervals
│       └── Always pass through text and errors immediately
│
├── Integration: ServiceOrchestrator
│   ├── Detect agent trigger (prefix: "code:", "agent:", or keywords)
│   ├── Save inbound media to temp files for agent access
│   ├── Route to AgentSpawner instead of direct LLM
│   ├── Stream coalesced events back to channel
│   └── Store agent session ID for "continue" support
│
└── Attachment bridging
    ├── Images → save to /tmp/irelay/ → reference path in prompt
    ├── Links → include URL in prompt text
    └── Videos → save to temp, reference path
```

**Tests**: CLI argument building, stream parsing, timeout enforcement

---

### Phase 5: Config + Integration + Polish
**Goal**: Usable without recompiling

```
Day 7-8
├── Config loading
│   ├── Read ~/.irelay/config.json
│   ├── ${VAR} substitution (pre-process string before JSON decode)
│   ├── .env file support
│   ├── Validate required fields
│   └── Apply defaults
│
├── CLI polish
│   ├── irelay init → generate example config
│   ├── irelay status → show channel health, active agents
│   └── Clear error messages on misconfiguration
│
├── Dual-mode routing
│   ├── Default → direct LLM chat (existing pipeline)
│   ├── "code:" prefix → agent spawner
│   ├── Configurable trigger patterns
│   └── Agent type selection ("codex:", "claude:")
│
└── Resilience
    ├── Provider retry (3 attempts, exponential backoff)
    ├── Channel reconnection
    ├── Agent crash recovery (error message to user)
    ├── Max 20 tool calls per agent turn
    └── SIGTERM/SIGINT graceful shutdown
```

---

## Dependency Graph

```
Phase 1 ─────────────────────────────────┐
  Channel Refactor                       │
  (ChannelKit, Shared, ProviderKit)      │
                                          │
    ┌─────────────────┬─────────────────┐ │
    ▼                 ▼                 ▼ │
Phase 2           Phase 3           Phase 4
  iMessage          WhatsApp          Agent
  Full Channel      Media             Spawner
    │                 │                 │
    └─────────────────┴─────────────────┘
                      │
                      ▼
                  Phase 5
                Config + Polish
```

**Phases 2, 3, 4 are fully parallel** after Phase 1.

## Estimated Scope

| Phase | LOC | Files | Parallel? |
|-------|-----|-------|-----------|
| 1: Channel Refactor | ~300 | 6-8 | — |
| 2: iMessage (via IMsgCore) | ~200 | 2-3 | Yes |
| 3: WhatsApp Media | ~250 | 2 | Yes |
| 4: Agent Spawner | ~500 | 5-6 | Yes |
| 5: Config + Polish | ~200 | 4-5 | — |
| **Total** | **~1,450** | **~20** | |

## Permissions Required

| Permission | What For | How to Grant |
|------------|----------|--------------|
| Full Disk Access | Read ~/Library/Messages/chat.db | System Settings → Privacy → Full Disk Access |
| Automation (Messages.app) | Send via AppleScript | Auto-prompted on first use |
