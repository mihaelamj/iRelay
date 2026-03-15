# iRelay Architecture

Apple-native personal AI assistant. Pure Swift. macOS + iOS.

## Vision

A local-first AI assistant that lives on your Apple devices. No Node.js, no Electron, no cross-platform compromises. One language, one ecosystem.

Inspired by [OpenClaw](https://github.com/openclaw/openclaw), rebuilt from scratch in Swift for the Apple platform.

## Constraints

- **Pure Swift** — no other languages, no bridging
- **Apple platforms only** — macOS + iOS
- **English default** — locale-aware architecture, no i18n work now
- **Local-first** — runs on your devices, no cloud dependency
- **Extreme Packaging** — maximum granular SPM modularization

## System Architecture

```
┌─────────────────────────────────────────────┐
│              iRelay Gateway               │
│         (Hummingbird WebSocket Server)       │
│                                              │
│  ┌───────────┐ ┌──────────┐ ┌───────────┐   │
│  │  Session   │ │  Agent   │ │   Cron    │   │
│  │  Manager   │ │  Router  │ │ Scheduler │   │
│  └───────────┘ └──────────┘ └───────────┘   │
│                                              │
│  ┌───────────────────────────────────────┐   │
│  │         Channel Plugin System         │   │
│  │  iMessage │ Telegram │ Slack │ ...    │   │
│  └───────────────────────────────────────┘   │
│                                              │
│  ┌───────────────────────────────────────┐   │
│  │         LLM Provider System           │   │
│  │  Claude │ OpenAI │ Ollama │ Gemini    │   │
│  └───────────────────────────────────────┘   │
│                                              │
│  ┌───────────────────────────────────────┐   │
│  │         Storage (GRDB/SQLite)         │   │
│  └───────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
        │                          │
   ┌────┴────┐              ┌──────┴──────┐
   │  macOS  │              │     iOS     │
   │ Menu Bar│              │    App      │
   │  App    │              │  (SwiftUI)  │
   │(SwiftUI)│              │             │
   └─────────┘              └─────────────┘
```

## Repository Structure (Extreme Packaging)

Follows the Cupertino pattern: single `Main.xcworkspace` at root, single `Package.swift` in `Packages/`, apps in `Apps/`.

```
iRelay/
├── Main.xcworkspace/                  # Xcode workspace (references Packages/)
│   ├── contents.xcworkspacedata
│   └── xcshareddata/
├── Apps/                              # App targets (separate .xcodeproj)
│   ├── iRelayMac/                  # macOS menu bar app (SwiftUI)
│   │   └── iRelayMac.xcodeproj
│   └── iRelayMobile/              # iOS app (SwiftUI)
│       └── iRelayMobile.xcodeproj
├── Packages/                          # ALL code lives here
│   ├── Package.swift                  # Single SPM manifest (all targets)
│   ├── Package.resolved
│   ├── Makefile
│   ├── VERSION
│   ├── Sources/
│   │   ├── Shared/                    # Foundation layer — models, config, paths
│   │   ├── Logging/                   # Logging framework
│   │   ├── Storage/                   # GRDB/SQLite persistence
│   │   ├── Networking/                # HTTP client, SSE streaming, WebSocket
│   │   ├── Security/                  # Keychain wrapper, credential management
│   │   │
│   │   ├── Gateway/                   # WebSocket server + protocol framing
│   │   ├── Sessions/                  # Session management + routing
│   │   ├── Agents/                    # Agent configuration + multi-agent routing
│   │   ├── Scheduling/                # Cron + task scheduling
│   │   │
│   │   ├── ChannelKit/                # Channel protocol + registry (no implementations)
│   │   ├── IMessageChannel/           # Native iMessage (Messages.framework)
│   │   ├── TelegramChannel/           # Telegram Bot API (raw HTTP)
│   │   ├── SlackChannel/              # Slack Web API + WebSocket
│   │   ├── DiscordChannel/            # Discord Gateway + REST
│   │   ├── SignalChannel/             # signal-cli subprocess
│   │   ├── MatrixChannel/             # Matrix HTTP API
│   │   ├── IRCChannel/                # Raw TCP (NWConnection)
│   │   ├── WebChatChannel/            # Built-in web UI via Hummingbird
│   │   │
│   │   ├── ProviderKit/               # LLM provider protocol + registry (no implementations)
│   │   ├── ClaudeProvider/            # Anthropic Messages API (SSE)
│   │   ├── OpenAIProvider/            # OpenAI Completions API (SSE)
│   │   ├── OllamaProvider/            # Local Ollama (OpenAI-compatible)
│   │   ├── GeminiProvider/            # Google Generative AI API
│   │   │
│   │   ├── Voice/                     # AVFoundation TTS + Speech STT
│   │   ├── MCPSupport/                # MCP server integration
│   │   ├── Memory/                    # Vector search, embeddings, recall
│   │   │
│   │   ├── Services/                  # High-level service layer (orchestration)
│   │   ├── CLI/                       # Main CLI executable (ArgumentParser)
│   │   │   ├── iRelay.swift        # @main entry point
│   │   │   └── Commands/              # Subcommands
│   │   │       ├── ServeCommand.swift
│   │   │       ├── ChatCommand.swift
│   │   │       ├── ConfigCommand.swift
│   │   │       ├── DaemonCommand.swift
│   │   │       └── StatusCommand.swift
│   │   │
│   │   └── TestSupport/               # Shared test utilities + fixtures
│   │
│   └── Tests/
│       ├── SharedTests/
│       ├── StorageTests/
│       ├── GatewayTests/
│       ├── SessionsTests/
│       ├── ChannelKitTests/
│       ├── TelegramChannelTests/
│       ├── SlackChannelTests/
│       ├── ProviderKitTests/
│       ├── ClaudeProviderTests/
│       ├── OpenAIProviderTests/
│       ├── VoiceTests/
│       ├── MemoryTests/
│       ├── CLITests/
│       └── CLICommandTests/
│           ├── ServeTests/
│           └── ChatTests/
│
├── Makefile                           # Root Makefile (delegates to Packages/Makefile)
├── .swiftlint.yml
├── .swiftformat
├── .pre-commit-config.yaml
├── .gitignore
├── LICENSE
├── README.md
├── ARCHITECTURE.md
├── CHANGELOG.md
└── install.sh
```

## Dependency Graph (Layered)

```
Foundation Layer (zero dependencies):
  ├── Shared            — Models, config types, paths, constants
  ├── Logging           → Shared
  └── Security          → Shared

Infrastructure Layer:
  ├── Storage           → Shared + Logging + GRDB
  ├── Networking        → Shared + Logging (HTTP, SSE, WebSocket helpers)
  └── Voice             → Shared + Logging (AVFoundation, Speech)

Protocol Layer (abstractions only, no implementations):
  ├── ChannelKit        → Shared + Logging
  └── ProviderKit       → Shared + Logging

Channel Implementations (one package per channel):
  ├── IMessageChannel   → ChannelKit + Shared
  ├── TelegramChannel   → ChannelKit + Shared + Networking
  ├── SlackChannel      → ChannelKit + Shared + Networking
  ├── DiscordChannel    → ChannelKit + Shared + Networking
  ├── SignalChannel     → ChannelKit + Shared
  ├── MatrixChannel     → ChannelKit + Shared + Networking
  ├── IRCChannel        → ChannelKit + Shared
  └── WebChatChannel    → ChannelKit + Shared + Gateway

Provider Implementations (one package per provider):
  ├── ClaudeProvider    → ProviderKit + Shared + Networking
  ├── OpenAIProvider    → ProviderKit + Shared + Networking
  ├── OllamaProvider    → ProviderKit + Shared + Networking
  └── GeminiProvider    → ProviderKit + Shared + Networking

Core Layer:
  ├── Gateway           → Shared + Logging + Hummingbird
  ├── Sessions          → Shared + Logging + Storage
  ├── Agents            → Shared + Logging + ProviderKit + Sessions
  ├── Scheduling        → Shared + Logging
  ├── MCPSupport        → Shared + Logging
  └── Memory            → Shared + Logging + Storage + ProviderKit

Service Layer:
  └── Services          → Sessions + Agents + ChannelKit + ProviderKit + Storage + Scheduling

Executable Layer:
  └── CLI               → Services + Gateway + all Channels + all Providers + ArgumentParser

Test Support:
  └── TestSupport       (no dependencies)
```

## Package.swift (Target Overview)

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "iRelay",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        // Foundation
        .library(name: "Shared", targets: ["Shared"]),
        .library(name: "Logging", targets: ["Logging"]),
        .library(name: "Security", targets: ["Security"]),
        .library(name: "Storage", targets: ["Storage"]),
        .library(name: "Networking", targets: ["Networking"]),

        // Protocols
        .library(name: "ChannelKit", targets: ["ChannelKit"]),
        .library(name: "ProviderKit", targets: ["ProviderKit"]),

        // Channels
        .library(name: "IMessageChannel", targets: ["IMessageChannel"]),
        .library(name: "TelegramChannel", targets: ["TelegramChannel"]),
        .library(name: "SlackChannel", targets: ["SlackChannel"]),
        .library(name: "DiscordChannel", targets: ["DiscordChannel"]),
        .library(name: "SignalChannel", targets: ["SignalChannel"]),
        .library(name: "MatrixChannel", targets: ["MatrixChannel"]),
        .library(name: "IRCChannel", targets: ["IRCChannel"]),
        .library(name: "WebChatChannel", targets: ["WebChatChannel"]),

        // Providers
        .library(name: "ClaudeProvider", targets: ["ClaudeProvider"]),
        .library(name: "OpenAIProvider", targets: ["OpenAIProvider"]),
        .library(name: "OllamaProvider", targets: ["OllamaProvider"]),
        .library(name: "GeminiProvider", targets: ["GeminiProvider"]),

        // Core
        .library(name: "Gateway", targets: ["Gateway"]),
        .library(name: "Sessions", targets: ["Sessions"]),
        .library(name: "Agents", targets: ["Agents"]),
        .library(name: "Services", targets: ["Services"]),
        .library(name: "Voice", targets: ["Voice"]),
        .library(name: "Memory", targets: ["Memory"]),
        .library(name: "MCPSupport", targets: ["MCPSupport"]),

        // Executables
        .executable(name: "irelay", targets: ["CLI"]),
    ],
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

        // DI
        .package(url: "https://github.com/pointfreeco/swift-dependencies.git", from: "1.0.0"),
    ]
)
```

## Core Protocols

### Channel (in ChannelKit)

```swift
public protocol Channel: Actor {
    var id: String { get }
    var status: ChannelStatus { get }

    func start() async throws
    func stop() async throws
    func send(_ message: OutboundMessage) async throws
    func onMessage(_ handler: @escaping @Sendable (InboundMessage) async -> Void)
}

public enum ChannelStatus: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}
```

### LLM Provider (in ProviderKit)

```swift
public protocol LLMProvider: Sendable {
    var id: String { get }
    var models: [ModelInfo] { get }

    func complete(
        _ messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<StreamEvent, Error>
}

public enum StreamEvent: Sendable {
    case text(String)
    case toolCall(ToolCall)
    case done(Usage)
}
```

### Message Types (in Shared)

```swift
public struct InboundMessage: Sendable {
    public let channelID: String
    public let senderID: String
    public let sessionID: String
    public let content: MessageContent
    public let timestamp: Date
    public let replyTo: String?
}

public struct OutboundMessage: Sendable {
    public let sessionID: String
    public let content: MessageContent
}

public enum MessageContent: Sendable {
    case text(String)
    case image(Data, mimeType: String)
    case audio(Data, mimeType: String)
    case file(Data, filename: String)
}
```

### Session (in Sessions)

```swift
public struct Session: Identifiable, Codable, Sendable {
    public let id: String
    public let channelID: String
    public let peerID: String
    public let agentID: String?
    public var history: [ChatMessage]
    public var metadata: SessionMetadata
    public let createdAt: Date
    public var lastActiveAt: Date
}
```

### Dependency Injection (Point-Free Dependencies)

```swift
// In ProviderKit
@DependencyClient
public struct LLMClient {
    public var complete: @Sendable (
        [ChatMessage], String, [ToolDefinition]
    ) async throws -> AsyncThrowingStream<StreamEvent, Error>
}

// In ViewModel
@Observable @MainActor
final class ChatViewModel {
    @ObservationIgnored @Dependency(\.llmClient) var llmClient
    private(set) var state: LoadingState<[ChatMessage]> = .idle
}
```

## Channel Implementation Details

| Channel | Protocol | Auth | Swift Approach |
|---------|----------|------|----------------|
| iMessage | Messages.framework / AppleScript | System permissions | Native macOS API |
| Telegram | HTTPS + long polling | Bot token | URLSession + async/await |
| Slack | WebSocket RTM + HTTPS | OAuth / Bot token | URLSessionWebSocketTask |
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

## Storage (GRDB + SQLite)

All persistence via GRDB in the Storage package:

- `sessions` — conversation sessions with channel/peer/agent binding
- `messages` — message history per session
- `config` — agent and channel configuration
- `secrets` — encrypted credentials (backed by Keychain via Security package)
- `embeddings` — vector storage for memory/recall (in Memory package)

## Apple-Native Advantages

| Feature | Framework | Package |
|---------|-----------|---------|
| Voice TTS | AVSpeechSynthesizer | Voice |
| Voice STT | Speech.framework | Voice |
| On-device AI | CoreML | Memory |
| Secrets | Keychain Services | Security |
| Daemon | LaunchAgent (macOS) | CLI |
| Networking | Network.framework | IRCChannel |
| Notifications | UserNotifications | Apps |
| Shortcuts | App Intents | Apps |
| Widgets | WidgetKit | Apps |

## CLI Commands

```
irelay serve            # Start gateway + all channels
irelay chat             # Interactive CLI chat
irelay config           # Manage agents, channels, providers
irelay config channels  # List/add/remove channels
irelay config providers # List/add/remove LLM providers
irelay config agents    # List/add/remove agents
irelay daemon install   # Install LaunchAgent
irelay daemon uninstall # Remove LaunchAgent
irelay status           # Show gateway + channel status
```

## Build System

### Root Makefile (delegates to Packages/)
```makefile
%:
	$(MAKE) -C Packages $@
```

### Packages/Makefile
```makefile
build:
	swift build -c release

build-debug:
	swift build

test:
	swift test

lint:
	swiftlint

format:
	swiftformat .

install:
	swift build -c release
	cp .build/release/irelay /usr/local/bin/

clean:
	swift package clean
```

## Phased Roadmap

### Phase 1 — Core + 2 Channels (4-6 weeks)

- [ ] Repo scaffolding (Main.xcworkspace, Packages/, Apps/)
- [ ] Package.swift with initial targets
- [ ] Shared + Logging + Storage + Networking packages
- [ ] ChannelKit + ProviderKit protocols
- [ ] Gateway (Hummingbird WebSocket)
- [ ] Sessions + Agents
- [ ] ClaudeProvider (SSE streaming)
- [ ] TelegramChannel (Bot API)
- [ ] IMessageChannel (macOS native)
- [ ] CLI with serve + chat commands
- [ ] macOS menu bar app (basic SwiftUI)

### Phase 2 — Expand (4-6 weeks)

- [ ] SlackChannel + DiscordChannel
- [ ] OpenAIProvider + OllamaProvider
- [ ] Voice package (TTS/STT)
- [ ] Security package (Keychain)
- [ ] iOS app (SwiftUI)
- [ ] Agent configuration + multi-agent routing
- [ ] Scheduling package (cron)
- [ ] Services orchestration layer

### Phase 3 — Polish (4-6 weeks)

- [ ] MatrixChannel + SignalChannel + IRCChannel + WebChatChannel
- [ ] GeminiProvider
- [ ] Memory package (embeddings + vector search)
- [ ] MCPSupport (Cupertino integration)
- [ ] App Intents / Shortcuts
- [ ] WidgetKit
- [ ] LaunchAgent daemon management
- [ ] install.sh

## Estimated Scope

| Metric | Estimate |
|--------|----------|
| SPM targets | ~30 libraries + 1 executable |
| Test targets | ~15-20 |
| Total Swift LOC | ~30,000-40,000 |
| Source files | ~200-300 |
| Channels | 8 |
| LLM Providers | 4 |
| Time to MVP (Phase 1) | 4-6 weeks |
| Time to full product | 12-18 weeks |
