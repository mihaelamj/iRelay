# iRelay

**Text your Mac. Run an AI agent.**

A Swift daemon that turns iMessage into a remote terminal for Claude Code. Send a message from your phone, your Mac picks it up, spawns Claude Code in your project directory, and texts you back the result.

No terminal. No SSH. No laptop open. Just iMessage.

<div align="center">

[![Blog Post](https://img.shields.io/badge/blog-aleahim.com-blue)](https://aleahim.com/blog/irelay/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20%7C%20iOS%2017%2B-lightgrey)](https://developer.apple.com)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

</div>

## Demo

<div align="center">
  <a href="https://www.youtube.com/shorts/ehOY7BnPOf0">
    <img src="https://img.youtube.com/vi/ehOY7BnPOf0/0.jpg" alt="iRelay Demo" width="300">
  </a>
  <br>
  <em>Creating a GitHub repo from iMessage while walking around the house</em>
</div>

## How It Works

```
iPhone (iMessage) → Mac (iRelay daemon) → Claude Code → response → iMessage
```

Send something like `irelayy fix the failing test` from your phone. Your Mac runs Claude Code against your project and texts you back what it did.

No web UI, no port forwarding, no VPN. iMessage as a transport layer.

## Architecture

```
┌─────────────────────────────────────────────┐
│              iRelay Gateway                 │
│           (Hummingbird HTTP Server)          │
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

### Channels

| Channel | Status | Transport |
|---------|--------|-----------|
| iMessage | :white_check_mark: Tested | Messages.framework / AppleScript |
| Telegram | :construction: Untested | Bot API (HTTPS + long polling / webhook) |
| Slack | :construction: Untested | Web API + Events API / Socket Mode |
| Discord | :warning: Partial ([#45](https://github.com/mihaelamj/iRelay/issues/45)) | REST send works, Gateway receive TBD |
| Signal | :construction: Untested | signal-cli subprocess |
| Matrix | :construction: Untested | Client-Server API + /sync polling |
| IRC | :construction: Untested | Raw TCP (Foundation streams) |
| WebChat | :construction: Untested | Hummingbird REST + HTML UI |
| WhatsApp | :construction: Untested | Business Cloud API + webhook |

**Not planned:** Email, SMS/Twilio, Microsoft Teams, Google Chat, Facebook Messenger, Mattermost, Line, Viber, Zulip.

### LLM Providers

| Provider | Status | Streaming |
|----------|--------|-----------|
| Claude | :white_check_mark: Tested | SSE via URLSession |
| OpenAI | :construction: Untested | SSE via URLSession |
| Ollama | :construction: Untested | NDJSON (no tool support) |
| Gemini | :construction: Untested | SSE via URLSession |

Only Claude is wired into `serve` and `agent-bridge` commands today. The other three providers compile and implement the `LLMProvider` protocol but are not yet registered in any CLI command.

### Core Modules

| Module | Status | Notes |
|--------|--------|-------|
| Gateway | :white_check_mark: Working | Hummingbird HTTP (webhooks, health, status) |
| Sessions | :white_check_mark: Working | GRDB-backed, persistent |
| Agents | :white_check_mark: Working | Routing, history, streaming |
| AgentSpawner | :white_check_mark: Working | Subprocess execution with concurrency limits |
| Storage | :white_check_mark: Working | GRDB/SQLite with migrations |
| Networking | :white_check_mark: Working | HTTP client + SSE streaming |
| Security | :white_check_mark: Working | macOS Keychain |
| Services | :white_check_mark: Working | Full orchestration pipeline |
| Voice | :white_check_mark: Working | macOS `say` command |
| MCPSupport | :white_check_mark: Working | JSON-RPC stdio client |
| Memory | :warning: Partial ([#49](https://github.com/mihaelamj/iRelay/issues/49)) | FTS5 search works, vector embeddings TBD |
| Scheduling | :warning: Partial ([#50](https://github.com/mihaelamj/iRelay/issues/50)) | Interval/daily works, cron parsing TBD |

## Build

```bash
make build          # release build
make build-debug    # debug build
make test           # run tests
make lint           # swiftlint
make format         # swiftformat
make install        # install to /usr/local/bin
```

## CLI

```bash
irelay serve            # start gateway + all channels
irelay chat             # interactive CLI chat
irelay agent-bridge     # iMessage ↔ Claude Code bridge
```

**TBD:**
- `irelay config` — manage agents, channels, providers ([#46](https://github.com/mihaelamj/iRelay/issues/46))
- `irelay status` — show gateway + channel status ([#47](https://github.com/mihaelamj/iRelay/issues/47))
- `irelay daemon install/uninstall` — LaunchAgent management ([#48](https://github.com/mihaelamj/iRelay/issues/48))

## Apps

**TBD:**
- macOS menu bar app ([#51](https://github.com/mihaelamj/iRelay/issues/51))
- iOS app ([#52](https://github.com/mihaelamj/iRelay/issues/52))

## Project Structure

Extreme Packaging — single `Package.swift` in `Packages/`, `Main.xcworkspace` at root. 29 SPM library targets, 1 executable.

```
iRelay/
├── Packages/
│   ├── Sources/
│   │   ├── Shared/             # Models, config, constants
│   │   ├── Storage/            # GRDB/SQLite persistence
│   │   ├── Networking/         # HTTP, SSE, WebSocket helpers
│   │   ├── Gateway/            # Hummingbird HTTP server
│   │   ├── Sessions/           # Session management + routing
│   │   ├── Agents/             # Agent config + multi-agent routing
│   │   ├── ChannelKit/         # Channel protocol (abstraction)
│   │   ├── IMessageChannel/    # Native iMessage
│   │   ├── TelegramChannel/    # Telegram Bot API
│   │   ├── ...                 # 7 more channel implementations
│   │   ├── ProviderKit/        # LLM provider protocol (abstraction)
│   │   ├── ClaudeProvider/     # Anthropic Messages API
│   │   ├── ...                 # 3 more provider implementations
│   │   ├── Voice/              # macOS TTS
│   │   ├── Memory/             # FTS search + recall
│   │   └── CLI/                # ArgumentParser entry point
│   └── Tests/
├── Apps/                       # macOS + iOS app targets (TBD)
└── Main.xcworkspace
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for full details — protocols, dependency graph, and implementation notes.

## Requirements

- Swift 6.0+
- macOS 14+ (Sonoma) / iOS 17+
- Xcode 16+

## Why the Double Y

Two daemons on the same Mac listening to iMessage would fight over every message. iRelay claims any message starting with `irelayy` (double y). Everything else gets ignored. Simple namespace partitioning over a shared channel.

## Blog Post

Read the full writeup: [iRelay: Text Your Mac, Run an AI Agent](https://aleahim.com/blog/irelay/)

## License

MIT
