# 02 — Gateway (WebSocket Control Plane)

The Gateway is the **central nervous system** of OpenClaw. It is a WebSocket server that everything connects to — the CLI, native apps (macOS/iOS/Android), the web dashboard, and all messaging channels. Every message, every event, every status update flows through the Gateway.

## What the Gateway Does

1. **Accepts WebSocket connections** from clients (apps, CLI, probes)
2. **Authenticates** each connection (token, password, or device signature)
3. **Routes messages** from channels to agents and back
4. **Manages channel lifecycles** (start, stop, restart, health monitoring)
5. **Broadcasts events** to all connected clients in real-time
6. **Streams AI responses** token-by-token to clients
7. **Handles health monitoring** and auto-recovery of failed channels

## Server Configuration

The Gateway listens on a configurable host and port:

- **Default address**: `ws://127.0.0.1:18789` (loopback only)
- **Max payload per message**: 25 MB
- **Max buffered bytes per connection**: 50 MB
- **Keepalive ping interval**: 30 seconds
- **Health refresh interval**: 60 seconds
- **Message deduplication window**: 5 minutes (max 1,000 entries)
- **Handshake timeout**: 10 seconds

These are defined as constants — not arbitrary choices but carefully tuned values.

## The WebSocket Protocol

All communication uses **JSON text frames** over WebSocket. There are three frame types:

### Request Frame (client sends to server)

When a client wants the server to do something, it sends a request:

```json
{
  "type": "req",
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "method": "agent.run",
  "params": { "sessionKey": "agent:main:main", "text": "Hello" }
}
```

- `type`: Always `"req"`
- `id`: A UUID that the client generates. Used to match the response
- `method`: The operation to perform (see Methods section below)
- `params`: Optional parameters for the method

### Response Frame (server sends to client)

The server responds to every request:

```json
{
  "type": "res",
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "ok": true,
  "payload": { "runId": "run-123", "status": "started" }
}
```

Or on failure:

```json
{
  "type": "res",
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "ok": false,
  "error": {
    "code": "AGENT_TIMEOUT",
    "message": "agent run exceeded timeout",
    "retryable": false
  }
}
```

### Event Frame (server pushes to client, unsolicited)

The server can push events at any time without a request:

```json
{
  "type": "event",
  "event": "agent",
  "payload": { "runId": "run-123", "stream": "tokens", "data": { "text": "Hello" } },
  "seq": 42,
  "stateVersion": { "presence": 5, "health": 3 }
}
```

- `seq`: A global sequence number for gap detection. If a client sees seq jump from 40 to 43, it knows it missed events
- `stateVersion`: Version counters for presence and health state, so clients can detect stale data

## Connection Lifecycle

### Step 1: WebSocket Open

Client opens a WebSocket connection to `ws://127.0.0.1:18789`.

### Step 2: Server Sends Challenge

Immediately after the connection opens, the server sends a challenge:

```json
{
  "type": "event",
  "event": "connect.challenge",
  "payload": { "nonce": "random-string-here", "ts": 1709904000000 }
}
```

The nonce is a random string the client must include in its connect request. This prevents replay attacks.

### Step 3: Client Sends Connect Request

The client responds with its identity and credentials:

```json
{
  "type": "req",
  "id": "uuid-here",
  "method": "connect",
  "params": {
    "minProtocol": 1,
    "maxProtocol": 1,
    "client": {
      "id": "GATEWAY_CLIENT",
      "displayName": "My Mac",
      "version": "2026.3.8",
      "platform": "darwin",
      "mode": "BACKEND"
    },
    "auth": {
      "token": "my-secret-token"
    },
    "role": "operator",
    "scopes": ["operator.admin"]
  }
}
```

Key fields in `client`:
- `id`: Client identifier (e.g., `GATEWAY_CLIENT`, `PROBE`, custom)
- `platform`: Operating system (`darwin`, `linux`, `win32`)
- `deviceFamily`: Device type (`iphone`, `android`, `mac`, etc.)
- `mode`: How this client operates:
  - `BACKEND`: Full operator (CLI, gateway itself)
  - `FRONTEND`: UI client (web dashboard, native app)
  - `PROBE`: Health check only

### Step 4: Server Validates and Responds

If authentication succeeds, the server sends `hello-ok` with a full state snapshot:

```json
{
  "type": "res",
  "id": "uuid-here",
  "ok": true,
  "payload": {
    "type": "hello-ok",
    "protocol": 1,
    "server": {
      "version": "2026.3.8",
      "connId": "conn-abc-123"
    },
    "features": {
      "methods": ["agent.run", "config.get", "..."],
      "events": ["agent", "chat", "presence", "tick", "..."]
    },
    "snapshot": {
      "presence": [],
      "health": {},
      "stateVersion": { "presence": 0, "health": 0 },
      "uptimeMs": 3600000,
      "sessionDefaults": {
        "defaultAgentId": "main",
        "mainKey": "agent:main:main",
        "mainSessionKey": "agent:main:main"
      },
      "authMode": "token"
    },
    "policy": {
      "maxPayload": 26214400,
      "maxBufferedBytes": 52428800,
      "tickIntervalMs": 30000
    }
  }
}
```

### Step 5: Active Session

Now the client is connected and can:
- Send requests (call methods)
- Receive events (broadcasts)
- Receive ticks (keepalive pings every 30 seconds)

### Step 6: Disconnect

Either side can close the connection:
- `1000`: Normal closure
- `1008`: Policy violation (auth failed, unauthorized)
- `1012`: Service restart
- `4000`: Tick timeout (client detected server is unresponsive)

## Authentication Modes

The Gateway supports four authentication modes:

### 1. No Auth (`"none"`)
No authentication required. Only safe on loopback.

### 2. Token Auth (`"token"`)
A shared secret token. The client sends it in `auth.token`. Set via config or `OPENCLAW_GATEWAY_TOKEN` env var.

### 3. Password Auth (`"password"`)
A shared password. Similar to token but uses `auth.password`.

### 4. Trusted Proxy (`"trusted-proxy"`)
For reverse proxy setups (Tailscale Serve, nginx). Trusts `X-Forwarded-For` header from configured proxy IPs.

### 5. Device Token (production)
Per-device cryptographic authentication:
- Device has a keypair
- Signs the challenge nonce with its private key
- Server verifies the signature with the stored public key
- Used by iOS/Android/macOS apps

### Rate Limiting

Authentication attempts are rate-limited:
- **Window**: 60 seconds
- **Max attempts**: 10 per window
- **Lockout**: 5 minutes after exceeding limit
- **Exempt**: Loopback addresses (127.0.0.1, ::1)

## Event Types

The Gateway can push these events to clients:

| Event | When | Payload |
|-------|------|---------|
| `connect.challenge` | Immediately on WebSocket open | `{ nonce, ts }` |
| `agent` | During AI response streaming | `{ runId, seq, stream, ts, data }` |
| `chat` | WebChat-specific messages | `{ runId, sessionKey, state, message, usage }` |
| `presence` | Client connects/disconnects | `{ entries: [...] }` |
| `tick` | Every 30 seconds | `{ ts }` |
| `health` | Every 60 seconds or on change | Full health snapshot |
| `shutdown` | Server shutting down | `{ reason, restartExpectedMs? }` |
| `heartbeat` | Heartbeat acknowledgement | Heartbeat data |
| `cron` | Scheduled job fires | Job details |
| `node.pair.requested` | Device wants to pair | Pairing info |
| `node.pair.resolved` | Pairing approved/denied | Resolution |
| `exec.approval.requested` | Command needs approval | Command details |
| `exec.approval.resolved` | Approval decision made | Decision |
| `voicewake.changed` | Wake word triggers updated | New triggers |
| `update.available` | New version detected | Version info |

### Agent Event Detail

The `agent` event is the most complex. It streams AI responses:

```json
{
  "type": "event",
  "event": "agent",
  "payload": {
    "runId": "run-abc-123",
    "seq": 1,
    "stream": "tokens",
    "ts": 1709904000000,
    "data": { "text": "Hello, " }
  }
}
```

The `stream` field tells you what kind of data:
- `"tokens"`: Text content being generated
- `"output"`: Final formatted output
- `"thinking"`: Reasoning/thinking content (if reasoning mode enabled)

## Channel Management

The Gateway manages all messaging channels through a **Channel Manager**:

### Channel State

Each channel+account combination has a runtime state:

```
{
  accountId: "default",
  enabled: true,
  configured: true,
  linked: true,
  running: true,
  connected: true,
  reconnectAttempts: 0,
  lastConnectedAt: 1709904000000,
  lastInboundAt: 1709903500000,
  lastOutboundAt: 1709903600000,
  activeRuns: 1
}
```

### Restart Policy

When a channel crashes, the Gateway restarts it with exponential backoff:

- **Initial delay**: 5 seconds
- **Max delay**: 5 minutes
- **Backoff factor**: 2x
- **Jitter**: 10% randomization
- **Max attempts**: 10 per channel

After 10 failures, the channel stays down until manually restarted.

### Health Monitoring

A health monitor runs every 5 minutes:

1. Checks each channel's connection status
2. Detects stale connections (no events for too long)
3. Auto-restarts channels that appear dead
4. Respects a 60-second startup grace period
5. Rate-limits restarts: max 10 per hour per channel
6. Cooldown: 2 check cycles between restarts

## Backpressure & Slow Clients

The Gateway tracks how much data is buffered per connection:

```
if (socket.bufferedAmount > 50MB) {
  // Client is too slow to keep up
  // Close connection with code 1008
}
```

For non-critical events (ticks, optional updates), the Gateway can **drop** events for slow clients instead of closing them. This prevents a slow mobile client from getting disconnected just because it can't keep up with verbose agent output.

## Message Deduplication

The Gateway deduplicates messages using an idempotency key:

- Each message can include an idempotency key
- Keys are stored for 5 minutes
- Maximum 1,000 keys tracked (oldest purged when exceeded)
- Prevents duplicate processing when clients retry

## Method Authorization

Not all clients can call all methods. Access is controlled by **roles** and **scopes**:

### Roles
- `operator`: Full access (default for CLI/backend)
- `node`: Limited access (edge devices like phones)
- `probe`: Read-only health checks

### Scopes
- `operator.admin`: Administrative operations (config changes, restarts)
- `operator.approvals`: Approve/deny execution requests
- `operator.pairing`: Manage device pairing

### Rate Limiting on Methods

Certain methods have their own rate limits:
- `config.apply`, `config.patch`, `update.run`: 3 per 60 seconds per client
- Returns `retryAfterMs` in error payload when limited

## Error Codes

| Code | Meaning | Retryable? |
|------|---------|-----------|
| `NOT_LINKED` | Node not linked to gateway | No |
| `NOT_PAIRED` | Device not paired | No |
| `AGENT_TIMEOUT` | Agent run exceeded timeout | No |
| `INVALID_REQUEST` | Malformed request | No |
| `UNAVAILABLE` | Service temporarily unavailable | Yes |

## Key Implementation Files

| File | Purpose |
|------|---------|
| `server.impl.ts` | Main startup, WebSocket server creation |
| `server-ws-runtime.ts` | WebSocket handler attachment |
| `server/ws-connection.ts` | Connection lifecycle management |
| `server/ws-connection/message-handler.ts` | Frame parsing, auth, routing |
| `server-broadcast.ts` | Event broadcasting with backpressure |
| `server-methods.ts` | Request handler dispatch |
| `server-chat.ts` | Chat event streaming |
| `server-node-events.ts` | Edge device event handling |
| `server-channels.ts` | Channel lifecycle management |
| `channel-health-monitor.ts` | Health checks and auto-restart |
| `server-maintenance.ts` | Tick, health, and cleanup timers |
| `server-close.ts` | Graceful shutdown |
| `client.ts` | Reference client implementation |
| `protocol/schema/frames.ts` | Frame type definitions |
| `protocol/schema/error-codes.ts` | Error code definitions |
| `auth.ts` | Authentication logic |
| `auth-rate-limit.ts` | Rate limiting for auth |
| `server-constants.ts` | All numeric constants |

## Swift Replication Notes

To replicate this in Swift:

1. **WebSocket server**: Use Hummingbird + HummingbirdWebSocket (already in iRelay)
2. **JSON protocol**: Define Codable structs for all frame types
3. **Authentication**: Implement token/password auth first, device auth later
4. **Channel manager**: An actor that tracks channel state and handles restarts
5. **Event broadcasting**: AsyncStream or Combine for pushing events to clients
6. **Health monitoring**: A background Task that periodically checks channels
7. **Backpressure**: Track NIOChannel writability for slow client detection
