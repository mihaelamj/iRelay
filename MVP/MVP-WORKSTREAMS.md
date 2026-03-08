# MVP Workstreams

## Overview

Four workstreams. The channel refactor is the foundation. Agent spawning is the core feature. Everything else supports these two.

---

## Workstream 1: Channel Protocol Refactor

**Why**: Multimodal must flow end-to-end. The protocol needs capabilities and limits so the orchestrator can make smart routing decisions, and so new channels are easy to add.

**What to build**:
- `ChannelCapabilities` OptionSet — text, images, video, audio, files, links, etc.
- `ChannelLimits` struct — size/format constraints per channel
- Add `capabilities` and `limits` to `Channel` protocol with backward-compat defaults
- Add `.video`, `.link`, `.compound` cases to `MessageContent`
- Add `textFallback` computed property to `MessageContent` for text-only channels
- Refactor `ChatMessage.content` from `String` to `[ContentBlock]` for multimodal provider support
- Update orchestrator to check capabilities before delivery

**Packages affected**: `ChannelKit`, `Shared`, `ProviderKit`, `ClaudeProvider`, `OpenAIProvider`, `Services`

**Non-breaking for**: All existing channel implementations (defaults cover them)

**Definition of done**: An image can flow from `InboundMessage` through `ChatMessage` to a provider and back out as `OutboundMessage`, with text-only channels getting a fallback description.

---

## Workstream 2: iMessage Full Channel

**Why**: Primary channel. Must handle inbound messages (including attachments) and outbound media.

**What to build**:

### Inbound (the hard part)
- Read `~/Library/Messages/chat.db` using GRDB (already a dependency)
- Query schema: `message` + `handle` + `attachment` + `chat_message_join` tables
- Poll loop with last-seen ROWID tracking
- Parse message text from `attributedBody` (NSKeyedArchiver blob) or `text` column
- Detect attachments via `message_attachment_join` → `attachment` table
- Read attachment files from `~/Library/Messages/Attachments/` paths
- Build `InboundMessage` with `.compound([.text(...), .image(...)])` for messages with media
- Deduplication: skip messages where `is_from_me = 1`

### Outbound media
- `send(.image)` → write to temp file → AppleScript `send (POSIX file "...")`
- `send(.file)` → same pattern
- `send(.compound)` → send each part sequentially

### Permissions
- Needs Full Disk Access or explicit SQLite read permission for `chat.db`
- Document this in setup instructions

**Packages affected**: `IMessageChannel`

**Definition of done**: Receive a text+image message in iMessage → SwiftClaw gets both → can reply with text and images.

---

## Workstream 3: WhatsApp Media Support

**Why**: Second channel for MVP. Already has text working, needs media.

**What to build**:

### Inbound media
- Parse webhook `type` field: `image`, `video`, `document`, `audio` (not just `text`)
- Download media via WhatsApp Media API: `GET /v21.0/{media-id}` → get URL → download bytes
- Populate `InboundMessage` with appropriate `MessageContent` case

### Outbound media
- Upload media: `POST /v21.0/{phone-number-id}/media` with multipart form data
- Send image: `POST /messages` with `type: "image"`, `image: { id: "media-id" }`
- Send document: same pattern with `type: "document"`
- Send video: same pattern with `type: "video"`

### Webhook types to handle
```json
{ "type": "image", "image": { "id": "media-id", "mime_type": "image/jpeg" } }
{ "type": "video", "video": { "id": "media-id", "mime_type": "video/mp4" } }
{ "type": "document", "document": { "id": "media-id", "filename": "file.pdf" } }
{ "type": "audio", "audio": { "id": "media-id", "mime_type": "audio/ogg" } }
```

**Packages affected**: `WhatsAppChannel`, `Networking` (media upload helper)

**Definition of done**: Send an image via WhatsApp → SwiftClaw receives it → can reply with images/files.

---

## Workstream 4: Coding Agent Spawner

**Why**: The core feature. This is what makes SwiftClaw useful.

**What to build**:
- `AgentSpawner` actor — spawn, stream, cancel agents
- `CLIBuilder` — construct `Process` arguments per agent type (Claude Code, Codex)
- `StreamParser` — parse stdout (JSON lines for Claude, text for Codex) into `AgentStreamEvent`
- `ProgressCoalescer` — buffer rapid events, emit meaningful updates at ~2s intervals
- `AgentSession` tracking — store session IDs for "continue" support
- Timeout enforcement — overall timeout + no-output timeout
- Attachment bridging — save inbound media to temp files, reference in prompts
- Integration with `ServiceOrchestrator` — wire spawner into the message pipeline

**Process flow**:
```
InboundMessage → Orchestrator → save media → build prompt → AgentSpawner.spawn()
    → stream events → coalesce → OutboundMessages → Channel.send()
```

**Packages affected**: New `AgentSpawner` package, `Services` (orchestrator wiring)

**Definition of done**: Send "fix the tests" via iMessage → Claude Code spawns → runs → result arrives in iMessage.

---

## Workstream 5: Config + Polish

**Why**: Must-have for anyone besides you to use it. Also needed for you to not hardcode paths.

**What to build**:
- Config loading with `${VAR}` substitution
- Required fields: `channels.imessage.enabled`, `agents.default.type`, `agents.default.workingDirectory`
- Optional: `agents.default.model`, `agents.default.budget`, `agents.default.allowedTools`
- `swiftclaw init` — generate example config
- Error messages that tell you exactly what's wrong
- Setup docs: Full Disk Access, API keys, channel setup

**Packages affected**: `Shared` (config types), `CLI`

---

## Dependency Graph

```
WS1: Channel Refactor ──────────────────────────┐
  (ChannelKit, Shared, ProviderKit)              │
                                                  │
WS2: iMessage Full ──── depends on WS1 ─────────┤
  (IMessageChannel)                               │
                                                  │
WS3: WhatsApp Media ── depends on WS1 ──────────┤
  (WhatsAppChannel)                               │
                                                  │
WS4: Agent Spawner ─── depends on WS1 ──────────┤
  (new AgentSpawner)   (needs multimodal msgs)    │
                                                  │
WS5: Config + Polish ─ depends on WS4 ───────────┘
  (CLI, Shared)
```

**WS2, WS3, WS4 can all run in parallel** after WS1 is done.

## Estimated Scope

| Workstream | New/Modified LOC | Files |
|-----------|-----------------|-------|
| WS1: Channel Refactor | ~300 | 6-8 |
| WS2: iMessage Full | ~400 | 1-2 |
| WS3: WhatsApp Media | ~250 | 1-2 |
| WS4: Agent Spawner | ~500 | 5-6 |
| WS5: Config + Polish | ~200 | 3-4 |
| **Total** | **~1,650** | **~20** |

Not a huge amount of code. The hard parts are iMessage `chat.db` parsing and the agent streaming pipeline. The rest is plumbing.
