# Gateway — Technical Implementation Details

## WebSocket Frame Protocol

### Frame Types

Every message over the WebSocket is a JSON string. There are exactly three frame types, distinguished by the `type` field:

**Request (client → server):**
```json
{
  "type": "req",
  "id": "unique-request-id",
  "method": "chat",
  "params": { ... }
}
```

**Response (server → client):**
```json
{
  "type": "res",
  "id": "unique-request-id",
  "ok": true,
  "payload": { ... },
  "error": null
}
```

**Event (server → client, push):**
```json
{
  "type": "event",
  "event": "tick",
  "payload": { "ts": 1709904000000 },
  "seq": 42,
  "stateVersion": { "presence": 7, "health": 3 }
}
```

### Error Shape

When a response has `ok: false`, the `error` field contains:

```json
{
  "code": "UNAUTHORIZED",
  "message": "Invalid token",
  "details": null,
  "retryable": false,
  "retryAfterMs": 0
}
```

### Payload Limits

```
MAX_PAYLOAD_BYTES   = 25 MB    (per-frame inbound limit)
MAX_BUFFERED_BYTES  = 50 MB    (per-connection send buffer)
```

If a client's send buffer exceeds `MAX_BUFFERED_BYTES`, the server detects it as a "slow consumer."

### Frame Encoding/Decoding

**Decoding (inbound):**
```
onMessage(rawData):
  1. text = rawDataToString(data)           # binary → UTF-8 string
  2. parsed = JSON.parse(text)              # parse JSON
  3. Validate against TypeBox schema        # structural check
  4. If schema error → send error response with INVALID_REQUEST
  5. Route based on parsed.type:
     - "req" → handleGatewayRequest()
     - Others → reject
```

**Encoding (outbound):**
```
send(frameObject):
  1. json = JSON.stringify(frameObject)
  2. Check socket.bufferedAmount > MAX_BUFFERED_BYTES?
     - YES and dropIfSlow=true → skip (don't send)
     - YES and required → close(1008, "slow consumer")
     - NO → socket.send(json)
  3. Catch send errors silently (socket likely closed)
```

## Connection State Machine

### States

```
┌──────────┐     challenge sent     ┌───────────┐     auth OK     ┌───────────┐
│  PENDING  │ ──────────────────── → │ HANDSHAKE │ ─────────────→ │ CONNECTED │
└──────────┘                         └───────────┘                 └───────────┘
     │                                    │                              │
     │ timeout (10s)                      │ auth fail                    │ close/error
     ▼                                    ▼                              ▼
┌──────────┐                         ┌───────────┐                ┌───────────┐
│  CLOSED   │                         │  CLOSED   │                │  CLOSED   │
└──────────┘                         └───────────┘                └───────────┘
```

### Step-by-Step Connection Flow

```
1. Client opens WebSocket to ws://127.0.0.1:18789

2. Server immediately sends connect.challenge:
   {
     type: "event",
     event: "connect.challenge",
     payload: { nonce: "<random-uuid>", ts: <now> }
   }

   Starts 10-second handshake timer

3. Client must respond with connect request:
   {
     type: "req",
     method: "connect",
     id: "<request-id>",
     params: {
       minProtocol: 1,
       maxProtocol: 1,
       client: { id: "control-ui", version: "1.0", platform: "darwin", mode: "ui" },
       auth: { token: "gateway-secret" },
       device: { id: "...", publicKey: "...", signature: "...", signedAt: ..., nonce: "..." },
       role: "operator",
       scopes: ["admin"]
     }
   }

4. Server validates (see Authentication below)

5. If OK, server responds with hello-ok:
   {
     type: "res",
     id: "<request-id>",
     ok: true,
     payload: {
       type: "hello-ok",
       protocol: 1,
       server: { version: "3.0", connId: "<uuid>" },
       features: { methods: [...], events: [...] },
       snapshot: { presence: [...], health: {...}, stateVersion: {...} },
       policy: { maxPayload: 25MB, maxBufferedBytes: 50MB, tickIntervalMs: 30000 },
       auth: { deviceToken: "...", role: "operator", scopes: ["admin"] }
     }
   }

   Clears handshake timer. Connection is now CONNECTED.
```

### Tick (Keep-Alive)

```
Server: every 30 seconds
  broadcast("tick", { ts: Date.now() }, { dropIfSlow: true })

Client: tracks lastTickTime
  if (now - lastTickTime > 2 × tickIntervalMs):
    → Stall detected → reconnect
```

## Authentication Flow

### 6-Step Authentication

```
Step 1: PROTOCOL NEGOTIATION
  if (client.maxProtocol < SERVER_VERSION or client.minProtocol > SERVER_VERSION):
    → reject: PROTOCOL_MISMATCH

Step 2: DEVICE IDENTITY VERIFICATION (if device provided)
  a. Derive deviceId from publicKey
     if (derived !== claimed device.id): → reject: device-id-mismatch

  b. Check signature freshness
     if (|now - signedAt| > 2 minutes): → reject: device-signature-stale

  c. Check nonce matches challenge
     if (device.nonce !== connectNonce): → reject: device-nonce-mismatch

  d. Verify signature (try v3 then v2 payload format)
     v3 includes: deviceId, clientId, mode, role, scopes, signedAt, token, nonce, platform, deviceFamily
     v2 includes: deviceId, clientId, mode, role, scopes, signedAt, token, nonce
     if (neither verifies): → reject: device-signature-invalid

Step 3: TOKEN/PASSWORD AUTH
  Resolve shared auth from params.auth (token or password)
  → authorizeWsControlUiGatewayConnect():
    Check token matches gateway config
    Check browser origin allowlist (for Control UI)
    Rate limit: 10 attempts per 60s per IP, 5-minute lockout

  Returns: { ok, method: "token"|"password"|"trusted-proxy"|"none" }

Step 4: DEVICE TOKEN AUTH (fallback if Step 3 fails)
  if (hasDevice and has deviceTokenCandidate and Step 3 failed):
    Verify device token against stored tokens
    if (valid): authOk = true, method = "device-token"
    else: record rate limit failure

Step 5: SCOPE CLEARANCE
  if (scopes requested but no shared auth provided):
    scopes = []    # clear all scopes — no privilege without auth

Step 6: DEVICE PAIRING
  if (device present and not yet paired):
    Check if device is already paired
    if (not paired):
      if (local client on loopback): auto-approve silently
      else: broadcast "device.pair.requested" and reject (client retries after approval)
```

### Rate Limiting

```
State per (scope, clientIp):
  attempts: timestamp[]     # sliding window
  lockedUntil: timestamp?   # lockout expiry

check(ip, scope):
  if (loopback address): return allowed
  if (lockedUntil > now): return blocked { retryAfterMs }
  prune attempts older than windowMs (60s)
  remaining = maxAttempts(10) - attempts.length
  return { allowed: remaining > 0, remaining }

recordFailure(ip, scope):
  if (loopback): return
  attempts.push(now)
  if (attempts.length >= maxAttempts):
    lockedUntil = now + lockoutMs(300s = 5 min)
```

## Request Routing

### Handler Dispatch

```
handleGatewayRequest(req, client):
  method = req.method

  # 1. Authorization check
  if (method !== "health"):
    if (role === "node"): only allow node-specific methods
    if (role === "operator"):
      if ("admin" in scopes): allow everything
      else: check method against scope map
    if (not authorized):
      respond(false, INVALID_REQUEST)
      unauthorizedFloodGuard.register()
      if (5+ unauthorized in 1 minute): close(1008)
      return

  # 2. Write rate limit
  if (method in ["config.apply", "config.patch", "update.run"]):
    budget = consumeControlPlaneWriteBudget(client)
    if (not budget.allowed):
      respond(false, RATE_LIMITED)
      return
    # Limit: 3 writes per 60s per actor

  # 3. Handler lookup
  handler = extraHandlers[method] ?? coreGatewayHandlers[method]
  if (not handler):
    respond(false, INVALID_REQUEST, "unknown method")
    return

  # 4. Async execution
  await handler({ req, params, client, respond, context })
  # Handler calls respond(ok, payload?, error?) when done
```

### Core Handlers

```
Gateway Methods:
  connect           → Connection handshake
  health            → Health check (no auth required)
  chat              → Send message to agent
  chat.abort        → Cancel in-progress chat
  agent             → Agent management
  agents            → List agents
  config.get        → Read configuration
  config.apply      → Replace configuration
  config.patch      → Partial config update
  device.pair.list  → List pending pairings
  device.pair.approve → Approve device
  node.list         → List connected nodes
  node.invoke       → Execute on remote node
  logs.tail         → Stream log output
  channels.status   → Channel health
  ... and 20+ more
```

## Event Broadcasting

### Broadcast Algorithm

```
State:
  seq = 0             # monotonic event counter
  clients = Set()     # all connected clients

broadcast(event, payload, opts?):
  if (clients.empty): return

  seq += 1
  frame = JSON.stringify({
    type: "event",
    event,
    payload,
    seq,
    stateVersion: opts?.stateVersion
  })

  for client in clients:
    # Scope check — some events require specific scopes
    if (not hasEventScope(client, event)):
      continue

    # Slow consumer detection
    slow = client.socket.bufferedAmount > MAX_BUFFERED_BYTES

    if (slow and opts?.dropIfSlow):
      continue              # silently drop for this client

    if (slow and not dropIfSlow):
      client.socket.close(1008, "slow consumer")
      continue              # force disconnect

    try:
      client.socket.send(frame)
    catch:
      # Socket already closed, ignore
```

### Event Scope Guards

Certain events are only sent to clients with matching scopes:

```
EVENT_SCOPE_GUARDS = {
  "exec.approval.requested":  ["operator.admin", "operator.approvals"],
  "exec.approval.resolved":   ["operator.admin", "operator.approvals"],
  "device.pair.requested":    ["operator.admin", "operator.pairing"],
  "node.pair.requested":      ["operator.admin", "operator.pairing"],
  // All other events: no scope required
}
```

### Targeted Broadcasting

For node-specific or connection-specific events:

```
broadcastToConnIds(event, payload, connIds, opts?):
  # Same as broadcast, but:
  # - No seq number (targeted, not global ordering)
  # - Only sends to connections in connIds set
```

## Health Monitoring

### Gateway Health Snapshot

```
buildGatewaySnapshot():
  return {
    presence: listSystemPresence(),        # active clients by role
    health: healthCache ?? {},             # channel health
    stateVersion: {
      presence: presenceVersion,           # incremented on connect/disconnect
      health: healthVersion                # incremented on health refresh
    },
    uptimeMs: process.uptime() × 1000,
    configPath, stateDir,
    authMode, updateAvailable
  }

refreshGatewayHealthSnapshot():
  if (refresh already in-flight): await existing promise
  else:
    snap = await getHealthSnapshot()       # probe all channels
    healthCache = snap
    healthVersion += 1
    broadcast("health", snap)              # push to all clients
```

### Channel Health Monitor

Runs every 5 minutes to check channel connections:

```
evaluateChannelHealth(status, channelId):
  # Grace period: skip check within 5 min of channel connecting
  if (connected < 5 minutes ago): return healthy

  # Stale event check: if no events received in 2 minutes
  if (connected but no events for 2 min): return unhealthy

  # Direct health check failed
  if (health check API error): return unhealthy

  # Channel not running
  if (not running): return unhealthy

onUnhealthy(channelId):
  # Cooldown: at least 10 min between restarts
  if (restarted < 10 min ago): skip

  # Hourly cap: max 10 restarts per hour
  if (restarts this hour >= 10): skip

  # Restart the channel
  await channelManager.stop(channelId)
  channelManager.resetRestartAttempts(channelId)
  await channelManager.start(channelId)
  recordRestartTimestamp()
```

### Connection Cleanup

```
onSocketClose(code, reason):
  # Track close metadata
  closeMeta = { handshakeState, durationMs, lastFrameType, code, reason }

  # Update presence
  if (client.presenceKey):
    upsertPresence(presenceKey, { reason: "disconnect" })
    broadcastPresenceSnapshot()     # notify all clients

  # Clean up node registration
  if (role === "node"):
    nodeId = nodeRegistry.unregister(connId)
    removeRemoteNodeInfo(nodeId)
    nodeUnsubscribeAll(nodeId)

  # Remove from client set
  clients.delete(client)
```

### Periodic Maintenance

Runs every 60 seconds:

```
maintenance():
  # 1. Dedupe cache cleanup (5-min TTL, 1000 max entries)
  for entry in dedupeCache:
    if (age > 5 min): delete
  if (dedupeCache.size > 1000): evict oldest

  # 2. Agent run sequence cleanup
  if (agentRunSeq.size > 10000): evict oldest 10000

  # 3. Chat abort controller cleanup
  for (runId, entry) in chatAbortControllers:
    if (now > entry.expiresAtMs): abortChatRunById(runId)

  # 4. Aborted run TTL (1 hour)
  for (runId, abortedAt) in abortedRuns:
    if (now - abortedAt > 1 hour): delete
```

### Unauthorized Flood Guard

Prevents clients from repeatedly sending unauthorized requests:

```
State per connection:
  unauthorizedCount = 0
  windowStart = now

registerUnauthorized():
  if (now - windowStart > 60s):
    # New window
    windowStart = now
    unauthorizedCount = 1
  else:
    unauthorizedCount += 1

  if (unauthorizedCount >= 5):
    socket.close(1008, "repeated unauthorized calls")
```
