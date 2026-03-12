# OpenClaw — Comprehensive Architecture Analysis

Reference analysis for iRelay. Based on [openclaw/openclaw](https://github.com/openclaw/openclaw) (v2026.3.3, ~800K LOC TypeScript).

---

## 1. What OpenClaw Is

A self-hosted personal AI assistant that runs locally. Connects to messaging channels (Telegram, Discord, Slack, WhatsApp, etc.) and routes messages through LLM providers (Claude, OpenAI, Gemini, Ollama, etc.). Everything runs on your machine — no cloud intermediary.

**Key numbers:**
- 25+ messaging channels
- 20+ LLM providers
- WebSocket gateway on port 18789
- File-based config + session storage (YAML + JSON)
- SQLite for vector memory/search only
- Plugin system for extensibility

---

## 2. System Architecture

```
                    ┌──────────────────────────┐
                    │     Gateway (WebSocket)   │
                    │        port 18789         │
                    │                           │
                    │  ┌─────────┐ ┌─────────┐  │
                    │  │  Auth   │ │  Rate   │  │
                    │  │Handshake│ │ Limiter │  │
                    │  └─────────┘ └─────────┘  │
                    └──────────┬───────────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
     ┌────────┴────┐  ┌───────┴──────┐  ┌──────┴──────┐
     │   Channel   │  │    Agent     │  │   Config    │
     │  Listeners  │  │   Runtime    │  │   Manager   │
     └──────┬──────┘  └──────┬───────┘  └─────────────┘
            │                │
   ┌────────┴────────┐      │
   │ Inbound Message │      │
   │  Normalization  │      │
   └────────┬────────┘      │
            │                │
            ▼                ▼
     ┌──────────────────────────┐
     │    Session Manager       │
     │  (per-agent, per-group)  │
     └──────────┬───────────────┘
                │
                ▼
     ┌──────────────────────────┐
     │    LLM Provider          │
     │  (streaming via SSE)     │
     └──────────┬───────────────┘
                │
                ▼
     ┌──────────────────────────┐
     │   Auto-Reply Dispatcher  │
     │  (chunking + delivery)   │
     └──────────┬───────────────┘
                │
                ▼
     ┌──────────────────────────┐
     │   Channel Outbound       │
     │  (per-channel adapters)  │
     └──────────────────────────┘
```

---

## 3. Gateway

**Location:** `/src/gateway/server.impl.ts`

- WebSocket server, default port 18789
- Bind modes: loopback (127.0.0.1), lan (0.0.0.0), tailnet, auto
- JSON-RPC-style frame protocol:
  - **Request:** `{type:"req", id:"uuid", method:"agent", params:{...}}`
  - **Response:** `{type:"res", id:"uuid", ok:true|false, payload:...}`
  - **Event:** `{type:"event", id:"uuid", event:"chat.stream", payload:...}`
- Zod schema validation on all messages
- Per-connection state: auth handshake, rate limiting, origin checking
- Client capabilities negotiated on connect (streaming, reasoning, etc.)
- Health/presence events broadcast to all clients

**Gateway methods** (`/src/gateway/server-methods/`):
- `agent` — send message to agent (main entry point)
- `agents` — list/manage agents
- `chat` — chat operations
- `config` — get/set/patch configuration
- `models` — list available models
- `cron` — scheduled jobs
- `devices` — device management
- `channels` — channel status/control
- `health` — health checks

**Authorization:** role-based (operator, node, viewer) + scope-based + rate-limited writes (3 per 60s).

---

## 4. Channels

### 4.1 Architecture: Two-Tier System

OpenClaw separates channels into two layers:

1. **Lightweight tier** (`/src/channels/dock.ts`, `/src/channels/registry.ts`):
   - Metadata, formatting rules, text chunk limits
   - Imported by shared code paths — no heavy dependencies
   - 21,400 lines in dock.ts alone (hardcoded per-channel config)

2. **Heavy tier** (`/extensions/<channel>/src/channel.ts`):
   - Full implementations: monitors, API clients, web login flows
   - Loaded as plugins, only when needed

### 4.2 Channel Plugin Interface

```typescript
type ChannelPlugin<ResolvedAccount, Probe, Audit> = {
  id: ChannelId;
  meta: ChannelMeta;
  capabilities: ChannelCapabilities;

  // Required
  config: ChannelConfigAdapter<ResolvedAccount>;

  // Optional adapters (compose as needed)
  gateway?: ChannelGatewayAdapter<ResolvedAccount>;
  outbound?: ChannelOutboundAdapter;
  security?: ChannelSecurityAdapter<ResolvedAccount>;
  pairing?: ChannelPairingAdapter;
  status?: ChannelStatusAdapter<ResolvedAccount, Probe, Audit>;
  auth?: ChannelAuthAdapter;
  onboarding?: ChannelOnboardingAdapter;
  threading?: ChannelThreadingAdapter;
  messaging?: ChannelMessagingAdapter;
  mentions?: ChannelMentionAdapter;
  commands?: ChannelCommandAdapter;
  streaming?: ChannelStreamingAdapter;
  directory?: ChannelDirectoryAdapter;
  heartbeat?: ChannelHeartbeatAdapter;
  actions?: ChannelMessageActionAdapter;
  agentPrompt?: ChannelAgentPromptAdapter;
  agentTools?: ChannelAgentToolFactory | ChannelAgentTool[];
};
```

### 4.3 Key Adapters

**ConfigAdapter** — account lifecycle (multi-account per channel):
- `listAccountIds`, `resolveAccount`, `defaultAccountId`
- `setAccountEnabled`, `deleteAccount`
- `isConfigured`, `describeAccount`
- `resolveAllowFrom`, `resolveDefaultTo`

**GatewayAdapter** — connection lifecycle:
- `startAccount`, `stopAccount`
- `loginWithQrStart`, `loginWithQrWait` (WhatsApp QR pairing)
- `logoutAccount`

**OutboundAdapter** — message delivery:
- Delivery modes: `direct`, `gateway`, `hybrid`
- Per-channel chunking (Telegram: 4000 chars, Discord: 2000)
- `sendText`, `sendMedia`, `sendPoll`, `sendPayload`

**SecurityAdapter** — DM policy:
- Policies: `pairing` (approval required), `allowlist`, `open`
- Per-channel, per-account allow-from lists
- Approval hints and normalization

### 4.4 Built-In Channels

| Channel | Protocol | Auth | Delivery | Text Limit |
|---------|----------|------|----------|------------|
| **Telegram** | Bot API (grammY) | Bot token | Direct | 4000 |
| **WhatsApp** | Baileys (reverse-eng) | QR pairing | Direct | 4000 |
| **Discord** | discord.js + Gateway | Bot token | Hybrid | 2000 |
| **Slack** | @slack/bolt Socket Mode | OAuth token | Gateway | 4000 |
| **Signal** | signal-cli REST | CLI link | Direct | 4000 |
| **IRC** | irc-framework | Nick/pass | Direct | 512 |
| **Google Chat** | HTTP webhook | Service account | Direct | 4096 |
| **iMessage** | imsg CLI | Local auth | Direct | — |

### 4.5 Channel Registration & Discovery

**Registry** (`/src/channels/registry.ts`):
- Ordered list: Telegram, WhatsApp, Discord, IRC, Google Chat, Slack, Signal, iMessage
- Each has metadata: label, docs path, blurb, icon

**Plugin loading** (`/src/channels/plugins/index.ts`):
- Plugins discovered from global registry
- Deduplicated, sorted by built-in order → custom order → alphabetical
- Cached with version tracking for hot reload

**External plugins** from:
- `$CONFIG_DIR/mpm/catalog.json`
- `$CONFIG_DIR/plugins/catalog.json`
- `OPENCLAW_PLUGIN_CATALOG_PATHS` env var

### 4.6 Message Normalization

Per-channel normalizers in `/src/channels/plugins/normalize/`:
- Discord: strip `<@!123>` mentions, snowflake IDs
- Telegram: chat/user ID extraction, group/supergroup differentiation
- Signal, WhatsApp, Slack: similar protocol-specific normalization

### 4.7 Message Actions

Post-delivery actions in `/src/channels/plugins/actions/`:
- Edit message, delete message
- Add/remove reactions
- Thread creation
- Per-channel implementations

---

## 5. LLM Providers

### 5.1 Provider Types

| Provider | API | Auth | Streaming |
|----------|-----|------|-----------|
| **Anthropic** | Messages API | API key | SSE |
| **OpenAI** | Chat Completions + Responses | API key / OAuth | SSE |
| **Google** | Generative AI | API key / OAuth | SSE |
| **AWS Bedrock** | Converse Stream | AWS SDK | Streaming |
| **Ollama** | OpenAI-compatible | None (local) | SSE |
| **GitHub Copilot** | OpenAI-compatible | OAuth + refresh | SSE |
| **LiteLLM** | OpenAI-compatible | API key | SSE |

### 5.2 Model Definition

```typescript
type ModelDefinitionConfig = {
  id: string;
  name: string;
  api: "anthropic-messages" | "openai-completions" | "openai-responses"
     | "google-generative-ai" | "bedrock-converse-stream";
  reasoning: boolean;
  inputTypes: ("text" | "image")[];
  cost: { input, output, cacheRead, cacheWrite };
  contextWindow: number;
  maxTokens: number;
  headers?: Record<string, string>;
  compat?: { thinkingFormat?, requiresToolResultName?, ... };
};
```

### 5.3 Provider Configuration

```typescript
type ModelProviderConfig = {
  baseUrl?: string;
  apiKey?: SecretInput;
  auth?: "api-key" | "aws-sdk" | "oauth" | "token";
  models: ModelDefinitionConfig[];
  headers?: Record<string, string>;
};
```

### 5.4 Model Selection & Failover

- Override precedence: explicit request param > session value > agent default > global default
- Auth profile rotation between API keys
- Bedrock auto-discovery from AWS region
- Merge mode: user config extends built-in catalog (or replaces entirely)

### 5.5 Streaming

- All providers stream via SSE (Server-Sent Events)
- WebSocket frames carry `EventFrame` with progressive content blocks
- Two streaming modes: **block streaming** (content blocks) and **tool streaming** (tool results)
- Raw stream capture via `OPENCLAW_RAW_STREAM` env var

### 5.6 Tool/Function Calls

- Tools defined in `/src/agents/pi-tools.ts` + plugin system
- Built-in tools: browser, canvas, nodes, cron, sessions, bash (approval-gated), system (approval-gated)
- Tool invocation through RPC bridge with approval workflows
- Results fed back for agentic loop

---

## 6. Agents

### 6.1 Agent Scope

- Multi-agent isolation: each agent gets dedicated workspace directory
- Default agent resolves from config or env
- Agent ID: slug format (normalized)

### 6.2 Agent Invocation

```typescript
// Gateway request
{
  method: "agent",
  params: {
    message: "...",
    agentId?: "...",
    sessionKey?: "...",
    thinking?: "off|minimal|low|medium|high|xhigh",
    model?: "claude-opus-4-6",
    attachments?: [{ type, mimeType, content }],
    deliver?: boolean,
    to?: "channel-scoped-id",
    channel?: "telegram|discord|..."
  }
}
```

### 6.3 System Prompt

- Built from conversation entries (role: user/assistant/tool)
- History context via `buildHistoryContextFromEntries`
- Extensible with `extraSystemPrompt` parameter
- Channel-specific prompt additions via `agentPrompt` adapter

### 6.4 Thinking/Reasoning Levels

Configurable per session or request: `off`, `minimal`, `low`, `medium`, `high`, `xhigh`

Format negotiated per model (OpenAI thinking, Qwen thinking, ZAI format).

### 6.5 Execution Approval

- Guards dangerous operations: bash, system.run
- Approval flows: explicit approve/deny, time-window approval
- Per-node policies for remote execution

---

## 7. Sessions

### 7.1 Storage

- **Format:** JSON files
- **Path:** `<workspace>/agents/<agentId>/sessions/<sessionId>.json`
- Per-group sessions: `sessions/<groupId>.json`
- Write strategy: atomic (temp file + rename)
- Concurrent access: write locks per session

### 7.2 Session Structure

```typescript
{
  sessionId: "uuid",
  model?: { id, alias, provider },
  channels?: { modelByChannel: Record<channel, model> },
  thinking?: "off" | "minimal" | ... | "xhigh",
  verbose?: "on" | "full" | "off",
  send?: { policy, enabled },
  queue?: { mode, maxSize },
  messages: [{ role, body, metadata, attachments }]
}
```

### 7.3 Session Key

Format: `<agentId>` or `<agentId>:<groupId>:<accountId>:<channel>`

Resolves which agent/session handles inbound messages.

### 7.4 Message History

- Stored as array of entries with role, body, metadata, attachments
- **Compaction:** token-aware pruning (oldest dropped when exceeding limits)
- Delivery routed back to original channel via send policy

### 7.5 Auto-Reply System

- Dispatcher queues outbound replies by session + channel
- Configurable per-channel message size limits (chunking)
- Retry: exponential backoff on delivery failures
- Heartbeat: periodic "alive" signals for long-running computations

---

## 8. Config System

### 8.1 Config File

- **Location:** `~/.openclaw/openclaw.yaml`
- **Schema:** Zod-validated

### 8.2 Sections

```yaml
gateway:
  bind: loopback|lan|tailnet
  auth:
    token: "..."
    oauth: { ... }
  port: 18789

agents:
  default: "main"
  defaults:
    model: "claude-sonnet-4-6"
    thinking: "medium"
    timeout: 300

channels:
  telegram:
    accounts:
      default:
        token: "${TELEGRAM_BOT_TOKEN}"
        dm:
          policy: pairing
          allowFrom: []
  discord:
    accounts:
      default:
        token: "${DISCORD_BOT_TOKEN}"
        guilds: { ... }

models:
  providers:
    anthropic:
      apiKey: "${ANTHROPIC_API_KEY}"
    openai:
      apiKey: "${OPENAI_API_KEY}"
    ollama:
      baseUrl: "http://localhost:11434"

plugins:
  installed: { ... }

cron:
  jobs: []

secrets:
  # Auth surface definitions (env vars, file paths)
```

### 8.3 Secrets Management

- Runtime snapshot activation (atomic, fail-safe)
- Auth surface state evaluation (active/inactive with reasons)
- Ref resolution: env vars (`${VAR}`), file paths
- Degradation handling when secrets unavailable

### 8.4 Doctor Utility

- Config issue detection (missing refs, invalid DM policies)
- Auto-repair capabilities
- Diagnostics export

---

## 9. Storage & Memory

### 9.1 No Traditional Database

OpenClaw deliberately avoids a traditional database:
- **Configuration:** YAML file
- **Sessions:** JSON files per agent/session
- **Rationale:** simple backups, Git-friendly, no DB server dependency

### 9.2 SQLite for Memory Only

- **Vector search:** sqlite-vec extension
- **Full-text search:** FTS5
- **Embedding cache:** avoids re-embedding
- Located in `/src/memory/sqlite.ts`

### 9.3 Memory System

- **Embedding providers:** OpenAI, Gemini, Voyage, Mistral, Ollama, local (node-llama)
- **Hybrid search:** BM25 (keyword) + vector (semantic) with result merging
- **Sync:** file watcher on workspace + session file tracking
- **Batch processing:** OpenAI batch API for cost optimization

---

## 10. CLI Commands

```
openclaw gateway [--port N] [--bind loopback|lan|tailnet]
openclaw agent --message "..." [--agentId ...] [--thinking high]
openclaw message send --to <id> --message "..."
openclaw onboard [--install-daemon]
openclaw doctor
openclaw config set/get/patch/apply
openclaw wizard
openclaw plugins install/uninstall/enable/disable
openclaw cron add/list/remove/run
openclaw pairing approve/list/reject
```

---

## 11. Plugin System

### 11.1 Plugin Types

1. **Channel plugins** — messaging platform integrations
2. **Provider plugins** — model auth + catalog (OAuth, device code, etc.)
3. **Tool plugins** — custom skills/tools for agents
4. **Hook plugins** — lifecycle hooks (message.in, message.out, agent.run)
5. **Memory plugins** — alternative vector backends (e.g., LanceDB)

### 11.2 Plugin Discovery

- Manifest registry via `plugin.yaml`
- Sources: npm packages, local workspace paths
- Catalog files: `$CONFIG_DIR/mpm/catalog.json`, `$CONFIG_DIR/plugins/catalog.json`

### 11.3 Plugin Context

```typescript
type OpenClawPluginToolContext = {
  config;
  workspaceDir;
  agentId;
  sessionKey;
  messageChannel;
  senderInfo;
  ownershipCheck;
  ephemeralSessionId;  // regenerates on /new
};
```

### 11.4 Bundled Extensions

Located in `/extensions/`:

**Channels:** discord, slack, telegram, whatsapp, signal, imessage, irc, googlechat + 15 more

**Providers:** google-gemini-cli-auth, qwen-portal-auth, minimax-portal-auth

**Memory:** memory-lancedb (LanceDB vector backend)

**Utilities:** diffs, diagnostics-otel, llm-task, open-prose, phone-control

---

## 12. Project Structure

```
openclaw/
├── src/                          # Core TypeScript source
│   ├── gateway/                  # WebSocket server + methods
│   │   ├── server.impl.ts        # Gateway server
│   │   ├── protocol/             # Frame protocol + schemas
│   │   └── server-methods/       # Per-method handlers
│   ├── channels/                 # Channel framework
│   │   ├── registry.ts           # Channel metadata + order
│   │   ├── dock.ts               # Lightweight config (21K lines)
│   │   └── plugins/              # Plugin interface + loading
│   │       ├── types.core.ts     # Core types
│   │       ├── types.adapters.ts # Adapter types
│   │       ├── types.plugin.ts   # Plugin definition
│   │       ├── normalize/        # Inbound normalization
│   │       ├── outbound/         # Outbound delivery
│   │       └── actions/          # Edit/delete/react
│   ├── agents/                   # Agent runtime + config
│   │   ├── model-auth.ts         # API key rotation
│   │   ├── model-selection.ts    # Model resolution
│   │   ├── models-config.ts      # Provider catalog
│   │   ├── pi-tools.ts           # Built-in tools
│   │   └── agent-scope.ts        # Per-agent isolation
│   ├── config/                   # Config types + I/O
│   │   ├── config.ts             # Config loading
│   │   ├── sessions.ts           # Session storage
│   │   ├── types.models.ts       # Model types
│   │   └── validation.ts         # Schema validation
│   ├── memory/                   # Vector search + embeddings
│   │   ├── manager.ts            # Memory manager
│   │   └── sqlite.ts             # SQLite + sqlite-vec
│   ├── secrets/                  # Credential management
│   ├── auto-reply/               # Reply dispatcher + queuing
│   ├── sessions/                 # Session events + routing
│   ├── plugins/                  # Plugin loader + runtime
│   ├── cli/                      # CLI commands
│   └── entry.ts                  # Main entry point
├── extensions/                   # Channel + provider plugins
│   ├── discord/
│   ├── telegram/
│   ├── slack/
│   ├── whatsapp/
│   ├── signal/
│   └── ... (19+ more)
├── apps/                         # Native apps
│   ├── macos/
│   ├── ios/
│   └── android/
├── ui/                           # Web UI
└── docs/                         # Documentation
```

---

## 13. Key Design Patterns

### Two-Tier Channel Architecture
Lightweight metadata (dock.ts) separated from heavy implementations (extensions/). Shared code only imports the light tier.

### Adapter Composition
Channel plugins compose optional adapters (config, gateway, outbound, security, threading, etc.). Only implement what the channel needs.

### Multi-Account Per Channel
Each channel supports multiple accounts (e.g., multiple Discord bots, multiple Telegram tokens). Account enable/disable without deletion.

### File-Based Everything
Config in YAML, sessions in JSON. No external database required. Git-friendly, simple backups.

### Streaming-First Protocol
WebSocket designed for progressive token/block streaming. Event frames carry partial content as it generates.

### Approval Workflows
Dangerous operations (bash, system calls) gated behind approval flows. Per-node policies for remote execution.

### Plugin Extensibility
Hooks + tools + channels + providers all extensible via plugin system. External plugins via npm or local paths.

---

## 14. What iRelay Must Replicate (MVP)

From OpenClaw's architecture, the minimum viable path:

1. **Gateway** — WebSocket server with JSON-RPC frames
2. **One channel** — Telegram (simplest: token auth, HTTP polling)
3. **One provider** — Claude (SSE streaming, tool calls)
4. **Session management** — per-agent message history
5. **Agent routing** — system prompt + model selection
6. **CLI** — `serve` (start gateway) + `chat` (interactive terminal)
7. **Config** — YAML/JSON config file with secret refs

Everything else (multi-account, plugins, memory, approval flows) is post-MVP.

---

## 15. iRelay Mapping

| OpenClaw Component | iRelay Package | Notes |
|---|---|---|
| `/src/gateway/` | Gateway | Hummingbird WebSocket instead of ws |
| `/src/channels/plugins/types.*` | ChannelKit | Swift protocol instead of TS type |
| `/extensions/<channel>/` | *Channel (per package) | One SPM target per channel |
| `/src/agents/models-config.ts` | ProviderKit | Swift protocol |
| `/src/agents/` | Agents | Agent config + routing |
| `/src/config/sessions.ts` | Sessions | GRDB instead of JSON files |
| `/src/config/config.ts` | Shared (config types) | Codable structs |
| `/src/memory/` | Memory | GRDB + sqlite-vec |
| `/src/secrets/` | IRelaySecurity | Keychain on macOS, file on Linux |
| `/src/auto-reply/` | Services | Orchestration layer |
| `/src/cli/` | CLI | ArgumentParser |
| `/src/plugins/` | Future (post-MVP) | — |
| `/src/channels/dock.ts` | ChannelKit (metadata) | Per-channel constants |
