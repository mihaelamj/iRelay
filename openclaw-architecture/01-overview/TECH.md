# Overview — Technical Implementation Details

## Monorepo Structure

### pnpm Workspace Layout

```
openclaw/
├── package.json              # Root manifest (pnpm workspace root)
├── pnpm-workspace.yaml       # Workspace member patterns
├── pnpm-lock.yaml            # Single lockfile for all packages
├── tsconfig.json             # Root TypeScript config
├── turbo.json                # Turborepo pipeline config
│
├── src/                      # Main application source (298+ files in infra/ alone)
│   ├── agents/               # Agent runtime, model config, auth profiles
│   ├── auto-reply/           # Message chunking, delivery
│   ├── browser/              # CDP automation, screenshots
│   ├── channels/             # Channel plugins (22 channels)
│   ├── cli/                  # Commander.js CLI (40+ commands)
│   ├── config/               # Config loading, sessions, migration
│   ├── cron/                 # Scheduling engine
│   ├── gateway/              # WebSocket server, HTTP endpoints
│   ├── infra/                # Foundational utilities (298 files)
│   ├── logging/              # Structured logging, redaction
│   ├── media/                # Media pipeline, MIME detection
│   ├── memory/               # Vector embeddings, FTS5
│   ├── plugins/              # Plugin SDK, hook system
│   ├── process/              # PTY, child process execution
│   ├── security/             # DM policies, pairing, content wrapping
│   ├── sessions/             # Session lifecycle
│   ├── skills/               # SKILL.md parsing, gating
│   ├── tts/                  # Text-to-speech providers
│   └── voice/                # Voice call management
│
├── extensions/               # Built-in plugins (42 extensions)
│   ├── voice-call/
│   ├── memory-default/
│   └── .../
│
├── dist/                     # Compiled output
└── tests/                    # Test suites
```

### Build System

```
Turborepo pipeline (turbo.json):
  build:    tsc + esbuild bundle
  test:     vitest
  lint:     eslint + prettier
  typecheck: tsc --noEmit

Dependencies flow:
  extensions → src → node_modules
  (extensions import from src via plugin-sdk subpath exports)
```

## Startup Sequence

### Gateway Boot

```
startGateway():
  # 1. Load configuration
  config = loadConfig()
  # (12-step pipeline: see 16-config/TECH.md)

  # 2. Initialize logging
  logger = createSubsystemLogger("gateway")
  pruneOldLogs()

  # 3. Resolve models
  ensureOpenClawModelsJson(config)
  # (autodiscover Ollama, vLLM, etc.)

  # 4. Load plugins
  registry = loadPlugins({ workspaceDir, config })
  # (discover → load → register → activate)

  # 5. Initialize auth store
  authStore = loadAuthProfileStore()
  clearExpiredCooldowns(authStore)

  # 6. Initialize memory databases
  for agent in config.agents.list:
    initMemoryDb(agent.id)
    # (create SQLite DB, load sqlite-vec, create schema)

  # 7. Initialize session store
  sessionStore = loadSessionStore(sessionsPath)

  # 8. Start channels
  for channel in enabledChannels:
    channelManager.start(channel)

  # 9. Start cron service
  cronService.start()

  # 10. Start WebSocket server
  wss = new WebSocketServer({ port: 18789 })
  attachGatewayWsConnectionHandler(wss)

  # 11. Start HTTP server (OpenAI-compatible)
  httpServer = createOpenAiHttpServer()
  httpServer.listen(18790)

  # 12. Start health monitor
  startChannelHealthMonitor()
  startMaintenanceTimer()

  # 13. Run gateway_start hooks
  await hookRunner.runVoidHook("gateway_start")
```

## Request Processing Pipeline

### Inbound Message Flow

```
Channel receives message
  │
  ├─ 1. NORMALIZE
  │     Platform-specific → common format
  │     { channel, from, to, text, timestamp, threadId, envelope }
  │
  ├─ 2. DM/GROUP ACCESS CHECK
  │     resolveDmGroupAccessDecision()
  │     → allow | block | pairing-required
  │
  ├─ 3. ROUTE
  │     resolveInboundRoute(message)
  │     → { agentId, sessionKey, deliveryContext }
  │
  ├─ 4. SESSION LOOKUP
  │     resolveSessionStoreEntry(sessionKey)
  │     → existing session or create new
  │
  ├─ 5. DEDUPE
  │     Check message ID against dedupe cache
  │     → skip if already processed (5-min TTL)
  │
  ├─ 6. HOOKS
  │     runModifyingHook("message_received", message)
  │     → plugins can modify or cancel
  │
  ├─ 7. MEDIA EXTRACTION
  │     parseMediaTokens(text)
  │     → extract MEDIA: tokens, download files
  │
  ├─ 8. ENQUEUE
  │     enqueueAgentTurn(agentId, sessionKey, message)
  │
  └─ 9. AGENT RUN
        runEmbeddedPiAgent(params)
        → (see 03-agents/TECH.md for full run loop)
```

### Outbound Delivery Flow

```
Agent produces response
  │
  ├─ 1. ENQUEUE (write-ahead)
  │     Save to delivery queue (crash recovery)
  │
  ├─ 2. NORMALIZE per channel
  │     Strip HTML for plain-text channels
  │     Normalize whitespace per platform
  │
  ├─ 3. FOR EACH payload:
  │     ├─ Run message_sending hook (can cancel/modify)
  │     ├─ Determine delivery mode:
  │     │   ├─ Channel-specific data → sendPayload()
  │     │   ├─ Text only → chunk and sendText()
  │     │   └─ Has media → sendMedia() with caption
  │     ├─ CHUNK if text > limit:
  │     │   ├─ Telegram: 4096 chars, markdown-aware
  │     │   ├─ Discord: 2000 chars
  │     │   ├─ IRC: 350 chars, fence-aware
  │     │   └─ Default: 4000 chars
  │     ├─ SEND via channel adapter
  │     └─ Run message_sent hook
  │
  └─ 4. CLEANUP queue
        Success → ackDelivery(queueId)
        Failure → retry with backoff (5s, 25s, 2m, 10m)
```

## Data Flow Architecture

### Message Lifecycle

```
Inbound:
  Platform → Channel Adapter → Normalize → Route → Session → Agent

Agent Processing:
  System Prompt Build → LLM Call → Stream Response → Tool Calls → Loop

Outbound:
  Agent Response → Chunk → Channel Adapter → Platform

Persistence:
  Session Store (sessions.json) ← metadata updates each turn
  JSONL Transcript (uuid.jsonl) ← append each message
  Memory DB (memory.db) ← sync embeddings periodically
```

### Token & Cost Flow

```
LLM Response includes usage:
  { input, output, cacheRead, cacheWrite }

Cost calculated per model:
  cost = tokens × (model.cost.input / 1000)

Accumulated per session:
  session.totalTokens += usage.totalTokens

Reported via:
  Gateway event: agent run usage
  Session store: totalTokens field
  CLI: session status command
```

## Error Recovery

### Crash Recovery Points

```
1. Delivery Queue (write-ahead):
   Pending messages survive process crash
   Re-delivered on startup (two-phase ack prevents duplicates)

2. Session Store (atomic writes):
   Temp file + rename pattern
   Never corrupted on crash (partial writes hit temp file)

3. JSONL Transcripts (append-only):
   Last line might be truncated
   Parser skips malformed lines gracefully

4. Cron Jobs (persistent state):
   Missed jobs detected on startup (compare lastRunAtMs)
   Executed immediately with backoff

5. Lock Files (staleness detection):
   PID + process start time in lock file
   Dead PID or recycled PID → stale lock removed
   Watchdog: force-release locks held > 5 minutes
```

### Process Supervision

```
macOS:  LaunchAgent plist
  launchctl kickstart -k gui/{uid}/{label}
  Fallback: bootstrap from plist, then retry

Linux:  systemd unit
  systemctl --user restart {unit}
  Fallback: systemctl restart {unit} (system-level)

Restart token system:
  SIGUSR1 triggers restart
  Token-based authorization prevents accidental restarts
  Cooldown: 30 seconds between restarts
  Pending work deferral: poll every 500ms, timeout after 30s
```

## Technology Stack

### Runtime

```
Node.js:        JavaScript runtime
TypeScript:     Type system (compiled via tsc + esbuild)
pnpm:           Package manager (workspace support)
Turborepo:      Build orchestration

Key Libraries:
  Commander.js   → CLI framework
  ws             → WebSocket server
  better-sqlite3 → SQLite driver
  sqlite-vec     → Vector similarity extension
  croner         → Cron expression parsing
  zod            → Schema validation
  JSON5          → Config parsing (comments, trailing commas)
  tslog          → Structured logging
  @lydell/node-pty → Pseudo-terminal support
  Playwright     → Browser automation (CDP abstraction)
  node-llama-cpp → Local embeddings (GGML models)
```

### Protocols

```
WebSocket:      Gateway control plane (ws://127.0.0.1:18789)
HTTP/REST:      OpenAI-compatible API (http://127.0.0.1:18790)
SSE:            Streaming responses (text/event-stream)
NDJSON:         Ollama streaming (newline-delimited JSON)
CDP:            Chrome DevTools Protocol (browser automation)
JSON-RPC:       CDP frame format
JSONL:          Session transcripts (one JSON per line)
```
