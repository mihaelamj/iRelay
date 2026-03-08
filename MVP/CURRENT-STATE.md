# SwiftClaw — Current State

## Build Status
- **Compiles**: Yes (Swift 6.0+, ~57s)
- **Tests pass**: Yes (14 suites)
- **Source**: ~4,500 LOC | **Tests**: ~1,000 LOC | **SPM targets**: 32

## What's Built

### Foundation (100%)
- **Shared** — Models, config types, message content enum, paths, constants
- **ClawLogging** — Structured logging
- **ClawSecurity** — Keychain integration
- **Storage** — GRDB/SQLite with migrations
- **Networking** — HTTP client, SSE streaming

### Protocols (100%)
- **ChannelKit** — Channel protocol, registry, status enum
- **ProviderKit** — LLM provider protocol, streaming events

### Channels (9 implemented, all text-only in practice)
Telegram, Slack, Discord, iMessage, WhatsApp, Signal, Matrix, IRC, WebChat

### Providers (4 implemented)
Claude, OpenAI, Ollama, Gemini — all with streaming completions

### Core Services
- **Gateway** — Hummingbird WebSocket server
- **Sessions** — Session manager with history
- **Agents** — Agent router
- **Services** — ServiceOrchestrator (full pipeline)
- **Voice/Memory/Scheduling/MCPSupport** — Various stages of completion

### CLI
- `serve` — Boots everything (working)
- `chat` — Interactive CLI (working)
- `config` / `status` — Scaffolded

## What's Relevant for MVP

### iMessage Channel — Skeleton
- **Outbound text**: Works (AppleScript → Messages.app)
- **Inbound**: Completely stubbed (`pollNewMessages()` is empty)
- **Attachments**: Not supported (rejects non-text content)
- **Approach**: AppleScript for sending, `chat.db` polling for receiving

### WhatsApp Channel — Text Only
- **Outbound text**: Works (Business Cloud API)
- **Inbound text**: Works (webhook → JSON decode)
- **Media**: Not handled (images/video/audio ignored in webhook parsing)
- **Approach**: REST API, webhook-based

### MessageContent Enum — Has the Cases, Nothing Uses Them
```swift
public enum MessageContent: Sendable {
    case text(String)
    case image(Data, mimeType: String)
    case audio(Data, mimeType: String)
    case file(Data, filename: String, mimeType: String)
    case location(latitude: Double, longitude: Double)
}
```
Every channel's `send()` does `guard let text = message.content.textValue` and throws on anything else. The types exist but the multimodal path is dead code.

### ChatMessage — Text Only
```swift
public struct ChatMessage: Sendable, Codable {
    public let role: ChatRole
    public let content: String  // ← String, not MessageContent
}
```
This is what goes to the LLM provider. It's a plain string. No way to pass images or files to the model. This needs to become multimodal for the vision use case.

## Gap Summary for MVP

| Component | Current | Needed |
|-----------|---------|--------|
| iMessage inbound | Stubbed | Poll chat.db, parse attachments |
| iMessage send media | No | AppleScript with POSIX file paths |
| WhatsApp inbound media | No | Parse image/video/document webhook types |
| WhatsApp send media | No | Media upload API endpoint |
| ChatMessage to provider | Text-only string | Multimodal content blocks |
| Channel protocol | Works but text-centric | Needs `capabilities` and media routing |
| Coding agent spawner | Not started | New package, Process-based |
| Agent run loop | Simple req/res | Tool loop with agent spawning |
