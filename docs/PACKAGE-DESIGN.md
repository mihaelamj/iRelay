# SwiftClaw Package Design

Maps the 12 layers from OPENCLAW-EXPLAINED.md to SPM packages. Flat hierarchy — all packages live in `Packages/Sources/`, one folder per package.

---

## Design Principles

1. **One package per responsibility** — no package does two jobs
2. **Flat layout** — no nested packages, all siblings in Sources/
3. **Protocols separate from implementations** — ChannelKit defines the interface, TelegramChannel implements it
4. **Admin logic separate from UI** — AdminKit returns plain data, never imports SwiftUI/UIKit
5. **Platform-aware** — macOS + Linux for everything except Voice and IMessage (macOS-only)
6. **Delivery is its own package** — not buried inside Services

---

## Layer → Package Mapping

### Layer 1: Gateway (The Front Door)

| Package | Responsibility |
|---------|---------------|
| **Gateway** | Hummingbird WebSocket server, frame protocol, connection management, auth handshake, health endpoint |

Depends on: Shared, ClawLogging, Hummingbird, HummingbirdWebSocket

---

### Layer 2: Channels (The Mailboxes)

| Package | Responsibility |
|---------|---------------|
| **ChannelKit** | `Channel` protocol, `ChannelStatus`, `ChannelRegistry`, `ChannelCapabilities`, message normalization protocol. No implementations. |
| **TelegramChannel** | Telegram Bot API — long polling, sendMessage, bot token auth |
| **DiscordChannel** | Discord Gateway WebSocket + REST — events, send, bot token |
| **SlackChannel** | Slack Socket Mode + Web API — OAuth token |
| **SignalChannel** | signal-cli subprocess — Process + pipe I/O |
| **MatrixChannel** | Matrix client-server API — sync + send, access token |
| **IRCChannel** | Raw TCP — NWConnection (macOS) / NIO (Linux), IRC protocol |
| **IMessageChannel** | Messages.framework / AppleScript — macOS only |
| **WebChatChannel** | Hummingbird serves HTML + WebSocket — built-in web UI |
| **WhatsAppChannel** | *(future)* — needs reverse-eng or Cloud API |
| **GoogleChatChannel** | *(future)* — webhook-based |

Each channel package depends on: ChannelKit, Shared, (optionally) Networking

---

### Layer 3: Sessions (The Sorting Room)

| Package | Responsibility |
|---------|---------------|
| **Sessions** | SessionManager (create/get/list/delete), session-channel-agent binding, message history management, session keys, session compaction (token-aware pruning) |

Depends on: Shared, ClawLogging, Storage

---

### Layer 4: Providers (The Brains)

| Package | Responsibility |
|---------|---------------|
| **ProviderKit** | `LLMProvider` protocol, `StreamEvent`, `ToolDefinition`, `ToolCall`, `ModelInfo`, `ProviderRegistry`. No implementations. |
| **ClaudeProvider** | Anthropic Messages API — SSE streaming, tool use |
| **OpenAIProvider** | OpenAI Chat Completions — SSE streaming, function calling |
| **OllamaProvider** | Local Ollama — OpenAI-compatible API |
| **GeminiProvider** | Google Generative AI — SSE streaming |
| **BedrockProvider** | *(future)* — AWS Bedrock Converse Stream |

Each provider package depends on: ProviderKit, Shared, Networking

---

### Layer 5: Agents (The Managers)

| Package | Responsibility |
|---------|---------------|
| **Agents** | AgentConfig (system prompt, model, tools), AgentRouter (route messages to agents), default agent fallback, agent CRUD |

Depends on: Shared, ClawLogging, ProviderKit, Sessions

---

### Layer 6: Delivery (The Reply Desk)

**This is new — not in current scaffold.**

| Package | Responsibility |
|---------|---------------|
| **Delivery** | AutoReplyDispatcher — queues outbound replies per session+channel. Chunking (per-channel text limits). Retry with backoff. Format conversion. Heartbeat for long-running responses. |

Depends on: Shared, ClawLogging, ChannelKit

Why separate: Currently buried in Services. But delivery logic (chunking, retry, formatting) is complex enough to be its own package. Services orchestrates; Delivery actually ships the message out.

---

### Layer 7: Storage (The Filing Cabinet)

| Package | Responsibility |
|---------|---------------|
| **Storage** | DatabaseManager (open/migrate/close), versioned migrations, SessionRecord CRUD, MessageRecord CRUD, ConfigRecord key-value store |

Depends on: Shared, ClawLogging, GRDB

---

### Layer 8: Secrets (The Lockbox)

| Package | Responsibility |
|---------|---------------|
| **ClawSecurity** | Keychain wrapper (macOS), file-based encrypted store (Linux), store/retrieve API keys + bot tokens, secret ref resolution (env vars, file paths) |

Depends on: Shared

---

### Layer 9: Memory (The Memory Room)

| Package | Responsibility |
|---------|---------------|
| **Memory** | Vector storage (GRDB + sqlite-vec), embedding generation (via provider), hybrid search (keyword BM25 + semantic vector), embedding cache |

Depends on: Shared, ClawLogging, Storage, ProviderKit

---

### Layer 10: Scheduler (The Clock)

| Package | Responsibility |
|---------|---------------|
| **Scheduling** | Cron expression parser, task scheduler (async, cancellable), scheduled message sending, timer management |

Depends on: Shared, ClawLogging

---

### Layer 11: Admin (The Control Panel)

**This is new — not in current scaffold.**

| Package | Responsibility |
|---------|---------------|
| **AdminKit** | All management operations as plain functions returning plain types. Channel CRUD, provider CRUD, agent CRUD, session search/delete/export, config get/set/reset/import/export, status/health checks, doctor (find + fix config issues). Zero UI imports. |

Depends on: Shared, ClawLogging, Storage, Sessions, Agents, ChannelKit, ProviderKit, Scheduling, ClawSecurity

Why separate: Must be consumable by iOS app, macOS app, web UI, and CLI equally. If admin logic lives in Services or CLI, it can't be reused.

---

### Layer 12: Plugins (Extensions)

**Future — not MVP.** Noting the design for later.

| Package | Responsibility |
|---------|---------------|
| **PluginKit** | *(future)* Plugin protocol, manifest format, discovery, loading, context injection |

---

### Cross-Cutting Packages

These don't map to a single layer but are used everywhere:

| Package | Responsibility |
|---------|---------------|
| **Shared** | Foundation types — models, config types, error types, constants, platform-aware paths |
| **ClawLogging** | Structured logging — wraps swift-log with categories |
| **Networking** | HTTP client, SSE parser, WebSocket client — shared by channels + providers |
| **TestSupport** | Test fixtures, mocks, helpers |

---

### Orchestration

| Package | Responsibility |
|---------|---------------|
| **Services** | Wires everything together: startup/shutdown lifecycle, message flow (channel → session → agent → provider → delivery → channel), channel + provider registration, graceful shutdown (SIGTERM/SIGINT) |

Depends on: Sessions, Agents, ChannelKit, ProviderKit, Storage, Scheduling, Delivery, AdminKit

---

### Executables

| Package | Responsibility |
|---------|---------------|
| **CLI** | Main entry point — `swiftclaw` binary. Subcommands: serve, chat, config, status, doctor. Imports Services + AdminKit + all channels + all providers. |

---

### Platform-Specific Packages

| Package | macOS | Linux | iOS |
|---------|-------|-------|-----|
| **Voice** | AVFoundation TTS + Speech STT | No-op stub | AVFoundation |
| **IMessageChannel** | Messages.framework | No-op stub | N/A |
| **MCPSupport** | Full | Full | N/A |
| Everything else | Full | Full | Library only |

---

## Complete Package List (38 packages)

```
Foundation (5):
  Shared, ClawLogging, ClawSecurity, Storage, Networking

Protocols (2):
  ChannelKit, ProviderKit

Channels (10):
  IMessageChannel, WhatsAppChannel, TelegramChannel,
  DiscordChannel, SlackChannel, SignalChannel,
  MatrixChannel, IRCChannel, WebChatChannel,
  GoogleChatChannel (future)

Providers (5):
  ClaudeProvider, OpenAIProvider, OllamaProvider, GeminiProvider,
  BedrockProvider (future)

Core (6):
  Gateway, Sessions, Agents, Delivery (NEW), Scheduling, Memory

Features (3):
  Voice, MCPSupport, AdminKit (NEW)

Orchestration (1):
  Services

Executable (1):
  CLI

Test Support (1):
  TestSupport

Future (1):
  PluginKit
```

---

## Dependency Graph (Bottom → Top)

```
                         CLI
                          │
                       Services
                     ╱    │    ╲
                   ╱      │      ╲
              AdminKit  Delivery  Gateway
              ╱  │  ╲      │
            ╱    │    ╲     │
     Agents Sessions  Scheduling
       │      │
  ProviderKit  Storage    ChannelKit
       │         │            │
       ├─────────┼────────────┤
       │         │            │
  Networking  ClawSecurity  ClawLogging
       │                      │
       └──────── Shared ──────┘

Channel implementations → ChannelKit + Shared + Networking
Provider implementations → ProviderKit + Shared + Networking
Memory → Shared + ClawLogging + Storage + ProviderKit
Voice → Shared + ClawLogging (macOS only)
MCPSupport → Shared + ClawLogging
```

---

## What Changed From Current Scaffold

| Change | Reason |
|--------|--------|
| **Added Delivery** | Chunking, retry, formatting is too much for Services. Own package. |
| **Added AdminKit** | Admin ops must be UI-free for iOS/macOS/web reuse. |
| **Added WhatsAppChannel** | MVP channel — WhatsApp Cloud API. |
| **Added BedrockProvider** | Noted as future, but reserved in the list. |
| **Added PluginKit** | Future extensibility, post-MVP. |
| **Voice stays** | macOS-only with Linux stub. Not MVP but keeps the slot. |
| **MCPSupport stays** | Cupertino integration. Not MVP but keeps the slot. |

---

## MVP Subset (15 packages)

Build these first, in this order:

```
1. Shared
2. ClawLogging
3. Networking
4. Storage
5. ClawSecurity
6. ProviderKit
7. ChannelKit
8. ClaudeProvider
9. IMessageChannel      ← MVP channel (macOS native)
10. WhatsAppChannel     ← MVP channel (Cloud API)
11. TelegramChannel     ← MVP channel (Bot API)
12. Sessions
13. Agents
14. Delivery
15. Services + CLI
```

Everything else is post-MVP.
