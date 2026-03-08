# 01 — Project Overview

## What Is OpenClaw?

OpenClaw is a **personal AI assistant** that runs on your own devices. Think of it as a private, self-hosted AI hub that sits between your messaging apps and large language models (LLMs).

Instead of going to a website to chat with an AI, OpenClaw lets you talk to AI through apps you already use — Telegram, Slack, Discord, iMessage, Signal, and many more. You send a message in any of these apps, and an AI responds right there in the same conversation.

### Core Philosophy

- **Local-first**: Runs on your Mac, Linux box, or Docker container — not someone else's server
- **Single-user**: Designed for one person (you), not a team or company
- **Privacy-respecting**: Your conversations stay on your devices
- **Multi-channel**: One AI brain, many messaging apps
- **Multi-provider**: Switch between Claude, GPT-4, Gemini, or local models seamlessly
- **Extensible**: Add new channels, skills, and features via plugins

## Technology Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Runtime** | Node.js 22+ | JavaScript execution engine |
| **Language** | TypeScript (ES2023, strict mode) | 100% typed codebase |
| **Package Manager** | pnpm 10.23 | Monorepo workspace management |
| **Build** | tsdown (bundler), tsx (execution) | Fast TypeScript compilation |
| **Linting** | Oxlint + Oxfmt | Rust-based, fast linting/formatting |
| **Testing** | Vitest 4.0 | Unit, integration, E2E, live tests |
| **CLI Framework** | Commander.js | Command-line argument parsing |
| **HTTP Server** | Node.js built-in | WebSocket + HTTP endpoints |
| **Database** | SQLite + SQLite-vec | Local persistence + vector search |
| **Container** | Docker (multi-stage) | Reproducible deployment |

## Monorepo Layout

OpenClaw is a single repository with everything in one place:

```
openclaw/
├── src/                    # Core TypeScript source (76 subdirectories)
│   ├── gateway/            # WebSocket control plane (the brain)
│   ├── agents/             # AI agent runtime (534 files)
│   ├── channels/           # Shared channel logic
│   ├── telegram/           # Telegram channel
│   ├── slack/              # Slack channel
│   ├── discord/            # Discord channel
│   ├── signal/             # Signal channel
│   ├── imessage/           # iMessage channel
│   ├── web/                # WebChat channel
│   ├── irc/                # IRC channel (in src)
│   ├── line/               # LINE channel
│   ├── providers/          # LLM provider integrations
│   ├── memory/             # Vector search + embeddings (100+ files)
│   ├── sessions/           # Conversation session management
│   ├── config/             # Configuration system (207 files)
│   ├── infra/              # Infrastructure layer (298 files)
│   ├── cli/                # CLI program structure
│   ├── commands/           # 295 CLI subcommand files
│   ├── browser/            # Chrome/Chromium control (130 files)
│   ├── media/              # Image/audio/video pipeline
│   ├── tts/                # Text-to-speech
│   ├── cron/               # Scheduled jobs
│   ├── security/           # DM policies, allowlists
│   ├── secrets/            # Credential management
│   ├── logging/            # Structured logging
│   ├── plugins/            # Plugin registry and loading
│   ├── plugin-sdk/         # SDK for extension developers
│   ├── process/            # Shell execution + PTY
│   ├── routing/            # Message routing logic
│   ├── context-engine/     # Prompt context building
│   ├── canvas-host/        # Visual workspace (React)
│   ├── hooks/              # Tool execution hooks
│   ├── wizard/             # Onboarding wizard
│   └── ... (20+ more)
│
├── extensions/             # 42 channel + feature plugins
│   ├── discord/            # Discord (extension version)
│   ├── bluebubbles/        # iMessage alternative
│   ├── matrix/             # Matrix protocol
│   ├── msteams/            # Microsoft Teams
│   ├── voice-call/         # Phone call integration
│   ├── memory-lancedb/     # LanceDB vector store
│   └── ... (36 more)
│
├── skills/                 # 43+ built-in skills
│   ├── apple-notes/        # Apple Notes integration
│   ├── github/             # GitHub automation
│   ├── obsidian/           # Obsidian vault access
│   ├── canvas/             # Visual workspace skill
│   └── ... (39 more)
│
├── apps/                   # Native platform apps
│   ├── macos/              # SwiftUI macOS menu bar app
│   ├── ios/                # iOS app
│   ├── android/            # Kotlin/Compose Android app
│   └── shared/             # Cross-platform Swift modules
│
├── ui/                     # Web dashboard + WebChat UI
├── packages/               # Legacy package code
├── docs/                   # Mintlify documentation
├── test/                   # Integration/E2E tests
├── scripts/                # Build and release scripts
├── Dockerfile              # Multi-stage Docker build
├── docker-compose.yml      # Gateway + CLI services
├── package.json            # Root workspace config
├── pnpm-workspace.yaml     # Monorepo workspace definition
└── vitest.config.ts        # Test configuration (9 configs total)
```

## High-Level Architecture

Here's how the pieces fit together:

```
┌──────────────────────────────────────────────────────────────────┐
│                        OpenClaw Gateway                          │
│                   (WebSocket Control Plane)                       │
│                    ws://127.0.0.1:18789                          │
│                                                                  │
│  ┌────────────┐  ┌────────────┐  ┌──────────┐  ┌────────────┐  │
│  │  Session    │  │   Agent    │  │  Cron    │  │  Health    │  │
│  │  Manager    │  │   Router   │  │ Scheduler│  │  Monitor   │  │
│  └────────────┘  └────────────┘  └──────────┘  └────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                  Channel Plugin System                    │   │
│  │  Telegram │ Slack │ Discord │ Signal │ iMessage │ IRC    │   │
│  │  WhatsApp │ Matrix │ Teams │ LINE │ WebChat │ + 10 more  │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                  LLM Provider System                      │   │
│  │  Claude │ GPT-4 │ Gemini │ Ollama │ OpenRouter │ + 15    │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────────┐      │
│  │  Memory     │  │  Skills      │  │  Plugin System    │      │
│  │  (Vectors)  │  │  (43+ tools) │  │  (42 extensions)  │      │
│  └─────────────┘  └──────────────┘  └───────────────────┘      │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Storage (SQLite + JSONL Files)               │   │
│  └──────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
        │              │              │              │
   ┌────┴────┐   ┌────┴────┐   ┌────┴────┐   ┌────┴────┐
   │  macOS  │   │   iOS   │   │ Android │   │  CLI    │
   │  App    │   │   App   │   │   App   │   │  Tool   │
   └─────────┘   └─────────┘   └─────────┘   └─────────┘
```

## How It All Connects (The Big Picture)

1. **You send a message** in Telegram (or Slack, Discord, iMessage, etc.)
2. **The channel plugin** for that app picks up your message
3. **The gateway** receives it and figures out which AI agent should handle it
4. **The agent runtime** builds a prompt with context, tools, and your message
5. **An LLM provider** (Claude, GPT-4, etc.) generates a response via SSE streaming
6. **The agent** processes the response, potentially calling tools (search, code, etc.)
7. **The gateway** routes the response back through the channel
8. **You see the reply** in the same messaging app

All of this happens on your own machine. The only external calls are to the LLM APIs (unless you use Ollama for fully local inference).

## Key Design Patterns

### Plugin Architecture
Almost everything is a plugin. Channels are plugins. Extensions are plugins. Skills are loadable units. This makes the system highly extensible without modifying core code.

### Event-Driven Streaming
The gateway uses WebSocket events for real-time communication. Agent responses stream token-by-token through SSE from the LLM, then through WebSocket to connected clients.

### Session Isolation
Each conversation (per channel, per user, per group) gets its own session with its own history. Sessions persist as JSONL files and can be compacted when they get too long.

### Auth Profile Rotation
When an API key hits a rate limit, OpenClaw automatically switches to the next available key. Keys have cooldown timers and failure tracking.

### Configuration-Driven
Everything is configurable via `~/.openclaw/openclaw.json`. Channels, providers, agents, skills, security policies — all driven by a single config file with Zod schema validation.

## Scale of the Codebase

| Metric | Count |
|--------|-------|
| Source directories | 76 |
| Extension plugins | 42 |
| Built-in skills | 43+ |
| CLI command files | 295 |
| Infrastructure files | 298 |
| Agent system files | 534 |
| Gateway files | 234 |
| Memory system files | 100+ |
| Config system files | 207 |
| Browser control files | 130 |
| Messaging channels | 22 |
| LLM providers | 20+ |
| Vitest test configs | 9 |
| Total estimated LOC | 200,000+ |
