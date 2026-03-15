# iRelay Architecture

A Swift daemon that turns iMessage (and other channels) into a remote terminal for LLM agents. Pure Swift. macOS + iOS.

## System Overview

```
┌─────────────────────────────────────────────┐
│              iRelay Gateway                 │
│           (Hummingbird HTTP Server)         │
│                                             │
│  ┌───────────┐ ┌──────────┐ ┌───────────┐  │
│  │  Session   │ │  Agent   │ │   Cron    │  │
│  │  Manager   │ │  Router  │ │ Scheduler │  │
│  └───────────┘ └──────────┘ └───────────┘  │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │       Channel Plugin System         │    │
│  │  iMessage │ Telegram │ Slack │ ...  │    │
│  └─────────────────────────────────────┘    │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │       LLM Provider System           │    │
│  │  Claude │ OpenAI │ Ollama │ Gemini  │    │
│  └─────────────────────────────────────┘    │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │       Storage (GRDB/SQLite)         │    │
│  └─────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

## Repository Structure

Single `Main.xcworkspace` at root, single `Package.swift` in `Packages/`.

```
iRelay/
├── Main.xcworkspace/
├── Packages/
│   ├── Package.swift              # 29 library products + 1 executable
│   ├── Makefile
│   ├── Sources/
│   │   ├── Shared/                # Models, config, constants, paths
│   │   ├── IRelayLogging/         # swift-log wrapper
│   │   ├── IRelaySecurity/        # macOS Keychain wrapper
│   │   ├── Storage/               # GRDB/SQLite persistence + migrations
│   │   ├── Networking/            # HTTPClient + SSE streaming
│   │   │
│   │   ├── ChannelKit/            # Channel protocol + ChannelRegistry
│   │   ├── IMessageChannel/       # AppleScript send + chat.db polling (GRDB)
│   │   ├── WhatsAppChannel/       # Business Cloud API + webhook
│   │   ├── TelegramChannel/       # Bot API long polling + webhook
│   │   ├── SlackChannel/          # Web API + Events API
│   │   ├── DiscordChannel/        # REST send + interactions (no Gateway WS)
│   │   ├── SignalChannel/         # signal-cli subprocess
│   │   ├── MatrixChannel/         # Client-Server API + /sync polling
│   │   ├── IRCChannel/            # Raw TCP streams
│   │   ├── WebChatChannel/        # Hummingbird REST + HTML UI
│   │   │
│   │   ├── ProviderKit/           # LLMProvider protocol + ProviderRegistry
│   │   ├── ClaudeProvider/        # Anthropic Messages API (SSE)
│   │   ├── OpenAIProvider/        # Chat Completions API (SSE)
│   │   ├── OllamaProvider/        # Local Ollama (NDJSON, no tools)
│   │   ├── GeminiProvider/        # Google Generative AI (SSE)
│   │   │
│   │   ├── Gateway/               # Hummingbird HTTP server (webhooks, health, status)
│   │   ├── Sessions/              # GRDB-backed session management
│   │   ├── Agents/                # AgentRouter (routing + history)
│   │   ├── AgentSpawner/          # Subprocess execution (claude, codex CLIs)
│   │   ├── Scheduling/            # Interval + daily scheduling
│   │   ├── Voice/                 # macOS `say` command TTS
│   │   ├── Memory/                # FTS5 full-text search + tagging
│   │   ├── MCPSupport/            # MCP client (JSON-RPC over stdio)
│   │   ├── Services/              # ServiceOrchestrator (message pipeline)
│   │   │
│   │   ├── CLI/                   # ArgumentParser entry point
│   │   │   ├── iRelay.swift       # @main
│   │   │   └── Commands/
│   │   │       ├── ServeCommand.swift
│   │   │       ├── ChatCommand.swift
│   │   │       ├── AgentBridgeCommand.swift
│   │   │       ├── IMessageTestCommand.swift
│   │   │       ├── ConfigCommand.swift      # stub
│   │   │       └── StatusCommand.swift      # stub
│   │   │
│   │   └── TestSupport/
│   │
│   └── Tests/                     # 20 test targets
│       ├── SharedTests/           # Comprehensive
│       ├── StorageTests/
│       ├── SessionsTests/
│       ├── AgentSpawnerTests/
│       ├── NetworkingTests/
│       ├── ChannelKitTests/
│       ├── IMessageChannelTests/
│       ├── WhatsAppChannelTests/
│       ├── TelegramChannelTests/
│       ├── SlackChannelTests/
│       ├── ClaudeProviderTests/
│       ├── OpenAIProviderTests/
│       ├── ProviderKitTests/
│       ├── GatewayTests/
│       ├── IRelayLoggingTests/
│       ├── IRelaySecurityTests/
│       ├── MemoryTests/
│       ├── VoiceTests/
│       ├── CLITests/
│       └── CLICommandTests/
│
├── Apps/                          # TBD: macOS menu bar + iOS apps
├── Makefile                       # Delegates to Packages/Makefile
├── LICENSE
├── README.md
└── ARCHITECTURE.md
```

## Dependency Graph

```
Foundation Layer (zero external deps):
  ├── Shared
  ├── IRelayLogging        → Shared + swift-log
  └── IRelaySecurity       → Shared

Infrastructure Layer:
  ├── Storage              → Shared + IRelayLogging + GRDB
  └── Networking           → Shared + IRelayLogging

Protocol Layer:
  ├── ChannelKit           → Shared + IRelayLogging
  └── ProviderKit          → Shared + IRelayLogging

Channel Implementations:
  ├── IMessageChannel      → ChannelKit + Shared + IRelayLogging + GRDB
  ├── WhatsAppChannel      → ChannelKit + Shared + Networking
  ├── TelegramChannel      → ChannelKit + Shared + Networking
  ├── SlackChannel         → ChannelKit + Shared + Networking
  ├── DiscordChannel       → ChannelKit + Shared + Networking
  ├── SignalChannel        → ChannelKit + Shared
  ├── MatrixChannel        → ChannelKit + Shared + Networking
  ├── IRCChannel           → ChannelKit + Shared
  └── WebChatChannel       → ChannelKit + Shared + Hummingbird

Provider Implementations:
  ├── ClaudeProvider       → ProviderKit + Shared + Networking
  ├── OpenAIProvider       → ProviderKit + Shared + Networking
  ├── OllamaProvider       → ProviderKit + Shared + Networking
  └── GeminiProvider       → ProviderKit + Shared + Networking

Core Layer:
  ├── Gateway              → Shared + IRelayLogging + Hummingbird + HummingbirdWebSocket
  ├── Sessions             → Shared + IRelayLogging + Storage + GRDB
  ├── Agents               → Shared + IRelayLogging + ProviderKit + Sessions
  ├── AgentSpawner         → Shared + IRelayLogging
  ├── Scheduling           → Shared + IRelayLogging
  ├── Voice                → Shared + IRelayLogging
  ├── Memory               → Shared + IRelayLogging + Storage + ProviderKit + GRDB
  └── MCPSupport           → Shared + IRelayLogging

Service Layer:
  └── Services             → Sessions + Agents + ChannelKit + ProviderKit + Shared + Storage + Scheduling + IRelayLogging

Executable:
  └── CLI                  → Services + Gateway + all Channels + all Providers + IRelaySecurity + Storage + Sessions + Agents + AgentSpawner + Voice + Memory + MCPSupport + ArgumentParser
```

## Core Protocols

### Channel (ChannelKit)

```swift
public protocol Channel: Actor {
    var id: String { get }
    var displayName: String { get }
    var status: ChannelStatus { get }
    var capabilities: ChannelCapabilities { get }
    var limits: ChannelLimits { get }

    func start() async throws
    func stop() async throws
    func send(_ message: OutboundMessage) async throws
    func onMessage(_ handler: @escaping @Sendable (InboundMessage) async -> Void)
}
```

`ChannelCapabilities` is an OptionSet: text, images, video, audio, files, links, reactions, typing, readReceipts, threads.

`ChannelLimits` has predefined limits for iMessage, WhatsApp, Telegram.

`ChannelRegistry` actor manages channel lifecycle (register, startAll, stopAll).

### LLMProvider (ProviderKit)

```swift
public protocol LLMProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var supportedModels: [ModelInfo] { get }

    func complete(
        _ messages: [ChatMessage],
        model: String,
        options: CompletionOptions
    ) -> AsyncThrowingStream<StreamEvent, Error>

    func validate() async throws -> Bool
}
```

`StreamEvent`: text, toolCall, usage, done, error.

`CompletionOptions`: maxTokens, temperature, topP, stopSequences, systemPrompt, tools, thinkingLevel.

`ProviderRegistry` actor manages provider lifecycle.

## Channel Implementation Details

| Channel | Send | Receive | Auth |
|---------|------|---------|------|
| iMessage | AppleScript → Messages.app | GRDB polling of chat.db | System permissions |
| WhatsApp | Meta Graph API v21.0 | Webhook handler | Phone Number ID + token |
| Telegram | `/sendMessage` REST | Long polling `/getUpdates` or webhook | Bot token |
| Slack | `/chat.postMessage` REST | Events API handler | Bot token |
| Discord | `/channels/{id}/messages` REST | Interactions only (no Gateway WS) | Bot token |
| Signal | `signal-cli send` subprocess | `signal-cli receive --json` subprocess | Phone number |
| Matrix | PUT `/send/m.room.message` | Long polling `/sync` | Access token |
| IRC | PRIVMSG over TCP stream | Read loop from InputStream | NICK/USER registration |
| WebChat | In-memory response store | POST `/chat/send` handler | Session cookie |

## Provider Implementation Details

| Provider | API | Streaming | Models |
|----------|-----|-----------|--------|
| Claude | Messages API | SSE | Sonnet 4, Opus 4, Haiku 3.5 |
| OpenAI | Chat Completions | SSE | GPT-4o, GPT-4o Mini, o3-mini |
| Ollama | OpenAI-compatible (localhost:11434) | NDJSON | Llama 3.3, Mistral, Code Llama |
| Gemini | Generative AI | SSE | Gemini 2.0 Flash, Pro |

All SSE-based providers share the same pattern: parse `data:` lines from `AsyncBytes`.

## CLI Commands

| Command | Status | Description |
|---------|--------|-------------|
| `irelay serve` | Working | Start gateway + register channels/providers via config |
| `irelay chat` | Working | Interactive CLI chat with streaming |
| `irelay agent-bridge` | Working | iMessage polling → Claude/Codex subprocess → reply |
| `irelay imessage-test` | Working | iMessage channel test utility |
| `irelay config` | Stub | Prints placeholder |
| `irelay status` | Stub | Prints "idle" |

### What `serve` actually wires up

ServeCommand currently registers:
- **Claude** provider (via Keychain or `ANTHROPIC_API_KEY` env var)
- **Telegram** channel (if configured in config file)
- Agents from config file (or a default Claude agent)
- ServiceOrchestrator for the message pipeline

Other providers and channels compile into the CLI binary but are **not yet wired** in ServeCommand.

### What `agent-bridge` does

AgentBridgeCommand is the primary way iRelay is used today:
- Polls iMessage via IMessageChannel
- Filters messages by `irelayy` prefix
- Spawns `claude` or `codex` CLI as a subprocess via AgentSpawner
- Sends response chunks back via iMessage
- Tracks sessions, saves to markdown, manages memory

## Storage Schema (GRDB/SQLite)

- `sessions` — conversation sessions with channel/peer/agent binding
- `messages` — message history per session

## External Dependencies

| Package | Version | Used by |
|---------|---------|---------|
| [Hummingbird](https://github.com/hummingbird-project/hummingbird) | 2.0+ | Gateway, WebChatChannel |
| [HummingbirdWebSocket](https://github.com/hummingbird-project/hummingbird-websocket) | 2.0+ | Gateway |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | 7.0+ | Storage, Sessions, IMessageChannel, Memory |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | 1.5+ | CLI |
| [swift-log](https://github.com/apple/swift-log) | 1.5+ | IRelayLogging |

## Platform Requirements

- Swift 6.0
- macOS 14+ (Sonoma) / iOS 17+
- Xcode 16+
