# SwiftClaw Architecture

Apple-native personal AI assistant. Pure Swift. macOS + iOS.

## Vision

A local-first AI assistant that lives on your Apple devices. No Node.js, no Electron, no cross-platform compromises. One language, one ecosystem.

Inspired by [OpenClaw](https://github.com/openclaw/openclaw), rebuilt from scratch in Swift for the Apple platform.

## Constraints

- **Pure Swift** — no other languages, no bridging
- **Apple platforms only** — macOS + iOS
- **English default** — locale-aware architecture, no i18n work now
- **Local-first** — runs on your devices, no cloud dependency

## System Architecture

```
┌─────────────────────────────────────────────┐
│              SwiftClaw Gateway              │
│         (Hummingbird WebSocket Server)      │
│                                             │
│  ┌───────────┐ ┌──────────┐ ┌───────────┐  │
│  │  Session   │ │  Agent   │ │   Cron    │  │
│  │  Manager   │ │  Router  │ │ Scheduler │  │
│  └───────────┘ └──────────┘ └───────────┘  │
│                                             │
│  ┌───────────────────────────────────────┐  │
│  │         Channel Plugin System         │  │
│  │  iMessage │ Telegram │ Slack │ ...    │  │
│  └───────────────────────────────────────┘  │
│                                             │
│  ┌───────────────────────────────────────┐  │
│  │         LLM Provider System           │  │
│  │  Claude │ OpenAI │ Ollama │ Gemini    │  │
│  └───────────────────────────────────────┘  │
│                                             │
│  ┌───────────────────────────────────────┐  │
│  │         Storage (GRDB/SQLite)         │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
        │                          │
   ┌────┴────┐              ┌──────┴──────┐
   │  macOS  │              │     iOS     │
   │ Menu Bar│              │    App      │
   │  App    │              │  (SwiftUI)  │
   │(SwiftUI)│              │             │
   └─────────┘              └─────────────┘
```

## Package Structure

```
SwiftClaw/
├── Package.swift
├── Sources/
│   ├── SwiftClawCore/          # Shared core library
│   │   ├── Gateway/            # WebSocket server + protocol
│   │   ├── Channels/           # Channel plugin protocol + registry
│   │   ├── Providers/          # LLM provider protocol + registry
│   │   ├── Sessions/           # Session management
│   │   ├── Agents/             # Agent routing + configuration
│   │   ├── Storage/            # GRDB/SQLite persistence
│   │   ├── Scheduling/         # Cron + task scheduling
│   │   └── Config/             # Configuration types
│   │
│   ├── Channels/               # Channel implementations
│   │   ├── IMessageChannel/    # Native iMessage (Messages.framework)
│   │   ├── TelegramChannel/    # Telegram Bot API (raw HTTP)
│   │   ├── SlackChannel/       # Slack Web API + WebSocket
│   │   ├── DiscordChannel/     # Discord Gateway + REST
│   │   ├── SignalChannel/      # signal-cli subprocess
│   │   ├── MatrixChannel/      # Matrix HTTP API
│   │   ├── IRCChannel/         # Raw TCP socket
│   │   └── WebChatChannel/     # Built-in web UI
│   │
│   ├── Providers/              # LLM provider implementations
│   │   ├── ClaudeProvider/     # Anthropic Messages API (SSE)
│   │   ├── OpenAIProvider/     # OpenAI Completions API (SSE)
│   │   ├── OllamaProvider/     # Local Ollama (OpenAI-compatible)
│   │   └── GeminiProvider/     # Google Generative AI API
│   │
│   ├── SwiftClawCLI/           # CLI entry point (ArgumentParser)
│   │
│   ├── SwiftClawKit/           # Shared code for Apple apps
│   │   ├── Voice/              # AVFoundation TTS + Speech STT
│   │   ├── Security/           # Keychain wrapper
│   │   └── Daemon/             # LaunchAgent management
│   │
│   └── SwiftClawMCP/           # MCP server integration
│       └── CupertinoModule/    # Apple docs via Cupertino
│
├── Apps/
│   ├── SwiftClawMac/           # macOS menu bar app (SwiftUI)
│   └── SwiftClawMobile/        # iOS app (SwiftUI)
│
└── Tests/
    ├── SwiftClawCoreTests/
    ├── ChannelTests/
    └── ProviderTests/
```

## Core Protocols

### Channel

```swift
protocol Channel: Actor {
    var id: String { get }
    var status: ChannelStatus { get }

    func start() async throws
    func stop() async throws
    func send(_ message: OutboundMessage) async throws
    func onMessage(_ handler: @escaping (InboundMessage) async -> Void)
}

enum ChannelStatus {
    case disconnected
    case connecting
    case connected
    case error(Error)
}
```

### LLM Provider

```swift
protocol LLMProvider: Sendable {
    var id: String { get }
    var models: [ModelInfo] { get }

    func complete(
        _ messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<StreamEvent, Error>
}

enum StreamEvent {
    case text(String)
    case toolCall(ToolCall)
    case done(Usage)
}
```

### Message Types

```swift
struct InboundMessage: Sendable {
    let channelID: String
    let senderID: String
    let sessionID: String
    let content: MessageContent
    let timestamp: Date
    let replyTo: String?
}

struct OutboundMessage: Sendable {
    let sessionID: String
    let content: MessageContent
}

enum MessageContent: Sendable {
    case text(String)
    case image(Data, mimeType: String)
    case audio(Data, mimeType: String)
    case file(Data, filename: String)
}
```

### Session

```swift
struct Session: Identifiable, Codable {
    let id: String
    let channelID: String
    let peerID: String
    let agentID: String?
    var history: [ChatMessage]
    var metadata: SessionMetadata
    let createdAt: Date
    var lastActiveAt: Date
}
```

## Channel Implementation Details

| Channel | Protocol | Auth | Swift Approach |
|---------|----------|------|----------------|
| iMessage | Messages.framework / AppleScript | System permissions | Native macOS API |
| Telegram | HTTPS + long polling | Bot token | URLSession + async/await |
| Slack | WebSocket RTM + HTTPS | OAuth / Bot token | URLSession + URLSessionWebSocketTask |
| Discord | WebSocket Gateway + HTTPS | Bot token | URLSessionWebSocketTask |
| Signal | signal-cli subprocess | Phone number | Process + pipe I/O |
| Matrix | HTTPS + long polling | Access token | URLSession |
| IRC | Raw TCP socket | None / NickServ | NWConnection (Network.framework) |
| WebChat | Hummingbird serves HTML + WS | Session cookie | Built-in |

## LLM Provider Details

| Provider | API | Streaming | Swift Approach |
|----------|-----|-----------|----------------|
| Claude | Messages API | SSE | URLSession + AsyncBytes line parsing |
| OpenAI | Chat Completions | SSE | URLSession + AsyncBytes line parsing |
| Ollama | OpenAI-compatible | SSE | Same as OpenAI |
| Gemini | generateContent | SSE | URLSession + AsyncBytes |

All providers use the same SSE streaming pattern — parse `data:` lines from `AsyncBytes`.

## Storage

**GRDB + SQLite** for all persistence:

- `sessions` — conversation sessions with channel/peer/agent binding
- `messages` — message history per session
- `config` — agent and channel configuration
- `secrets` — encrypted credentials (backed by Keychain on macOS/iOS)
- `embeddings` — vector storage for memory/recall (optional)

## Apple-Native Advantages

| Feature | Framework | What it gives you |
|---------|-----------|-------------------|
| Voice TTS | AVSpeechSynthesizer | Read responses aloud |
| Voice STT | Speech.framework | Dictate messages |
| On-device AI | CoreML | Local inference, no API call |
| Secrets | Keychain Services | Secure credential storage |
| Daemon | LaunchAgent (macOS) | Always-on background service |
| Networking | Network.framework | TCP/UDP/WebSocket with TLS |
| Notifications | UserNotifications | Alert on incoming messages |
| Shortcuts | Intents / App Intents | Siri + Shortcuts integration |
| Widgets | WidgetKit | Quick status on home screen |
| Share | Share Extension | Send content to SwiftClaw |

## Phased Roadmap

### Phase 1 — Core + 2 Channels (4-6 weeks)

- [ ] Swift Package with core protocols
- [ ] Hummingbird WebSocket gateway
- [ ] Session management + GRDB storage
- [ ] Claude provider (streaming)
- [ ] Telegram channel (Bot API)
- [ ] iMessage channel (macOS native)
- [ ] CLI entry point (ArgumentParser)
- [ ] macOS menu bar app (basic)

### Phase 2 — Expand (4-6 weeks)

- [ ] Slack + Discord channels
- [ ] OpenAI + Ollama providers
- [ ] Voice TTS/STT (AVFoundation + Speech)
- [ ] iOS app (SwiftUI)
- [ ] Agent configuration + routing
- [ ] Cron scheduling
- [ ] Keychain integration

### Phase 3 — Polish (4-6 weeks)

- [ ] Matrix + Signal + IRC + WebChat channels
- [ ] Gemini provider
- [ ] Memory/vector search (embeddings)
- [ ] MCP integration (Cupertino module)
- [ ] Shortcuts/Intents
- [ ] WidgetKit
- [ ] LaunchAgent daemon management

## Dependencies

```swift
// Package.swift
dependencies: [
    // Server
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.0.0"),

    // CLI
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),

    // Database
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),

    // Logging
    .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),

    // Networking (for non-Apple platforms, if ever needed)
    .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.20.0"),
]
```

## Estimated Scope

| Metric | Estimate |
|--------|----------|
| Total Swift LOC | ~30,000-40,000 |
| Source files | ~200-300 |
| Channels | 8 |
| LLM Providers | 4 |
| Time to MVP (Phase 1) | 4-6 weeks |
| Time to full product | 12-18 weeks |
