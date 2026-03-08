# Channels — Technical Implementation Details

## Channel Plugin Interface

### Core Contract

Every channel implements this plugin structure:

```typescript
ChannelPlugin<ResolvedAccount, Probe, Audit> = {
  id: ChannelId,                              // "telegram", "discord", etc.
  meta: ChannelMeta,                          // display name, icon, docs URL
  capabilities: ChannelCapabilities,          // what this channel supports
  config: ChannelConfigAdapter<ResolvedAccount>,
  outbound?: ChannelOutboundAdapter,
  gateway?: ChannelGatewayAdapter<ResolvedAccount>,
  status?: ChannelStatusAdapter<ResolvedAccount, Probe, Audit>,
}
```

### Required Methods

**Configuration Adapter:**
```
listAccountIds(cfg) → string[]
  Enumerate all configured accounts for this channel

resolveAccount(cfg, accountId?) → ResolvedAccount
  Load and validate account config

isEnabled?(account, cfg) → boolean
  Check if account is active

isConfigured?(account, cfg) → boolean | Promise<boolean>
  Validate setup (API keys present, etc.)

describeAccount?(account, cfg) → ChannelAccountSnapshot
  Return status snapshot for UI
```

**Outbound Delivery Adapter:**
```
sendText(ctx: ChannelOutboundContext) → Promise<OutboundDeliveryResult>
  Send a text message

sendMedia(ctx: ChannelOutboundContext) → Promise<OutboundDeliveryResult>
  Send media with optional caption

sendPayload(ctx: ChannelOutboundPayloadContext) → Promise<OutboundDeliveryResult>
  Send channel-specific structured data (buttons, cards, etc.)

sendPoll?(ctx: ChannelPollContext) → Promise<ChannelPollResult>
  Send interactive poll

resolveTarget?(params) → { ok, to } | { ok: false, error }
  Resolve a human-readable target to a platform ID

chunker?: (text, limit) → string[]
  Custom text splitting function

chunkerMode?: "text" | "markdown"
  "text" splits blind, "markdown" respects code blocks

textChunkLimit?: number
  Maximum characters per chunk
```

**Gateway Lifecycle Adapter:**
```
startAccount(ctx: ChannelGatewayContext) → Promise<unknown>
  Connect to platform, start listening

stopAccount(ctx: ChannelGatewayContext) → Promise<void>
  Disconnect, cleanup resources

loginWithQrStart?(params) → Promise<ChannelLoginWithQrStartResult>
  Begin QR code login flow (WhatsApp)

loginWithQrWait?(params) → Promise<ChannelLoginWithQrWaitResult>
  Wait for QR scan completion

logoutAccount(ctx: ChannelLogoutContext) → Promise<ChannelLogoutResult>
  Full logout and credential cleanup
```

**Health & Status Adapter:**
```
probeAccount?(params) → Promise<Probe>
  Lightweight connectivity check

auditAccount?(params) → Promise<Audit>
  Deep account validation

buildAccountSnapshot?(params) → Promise<ChannelAccountSnapshot>
  Full status snapshot

collectStatusIssues?(snapshots) → ChannelStatusIssue[]
  Aggregate errors across accounts
```

## Message Normalization

### Inbound Flow

```
Platform receives raw message
  │
  ├─ 1. Parse platform-specific format
  │     Telegram: Update object
  │     Discord: Message event
  │     Slack: Event payload
  │
  ├─ 2. Normalize to common format
  │     {
  │       channel: "telegram",
  │       from: "user123",
  │       to: "bot456",
  │       text: "Hello",
  │       timestamp: 1709904000000,
  │       replyToId: "msg789",
  │       threadId: "thread123",
  │       envelope: { ...platform-specific metadata }
  │     }
  │
  ├─ 3. Route via resolveInboundRouteEnvelopeBuilder()
  │     Determines: which agent, which session key
  │
  └─ 4. Deliver to agent runtime
```

### Outbound Normalization

```
normalizePayloadForChannelDelivery(payload, channelId):
  hasMedia = payload.mediaUrl or payload.mediaUrls?.length > 0
  hasChannelData = payload.channelData and Object.keys(...).length > 0

  # WhatsApp-specific: strip leading blank lines
  normalizedText = channelId === "whatsapp"
    ? payload.text.replace(/^(?:[ \t]*\r?\n)+/, "")
    : payload.text

  # Empty text with no media/data → skip (return null)
  if (not normalizedText.trim()):
    if (not hasMedia and not hasChannelData): return null
    return { ...payload, text: "" }

  if (normalizedText === payload.text): return payload
  return { ...payload, text: normalizedText }
```

### Plain-Text Surface Sanitization

Channels that can't render HTML (WhatsApp, Signal, SMS, IRC, Telegram, iMessage, GoogleChat):

```
sanitizeForPlainText(html):
  html = html.replace(/<br\s*\/?>/g, "\n")
  html = html.replace(/<b>(.*?)<\/b>/g, "*$1*")
  html = html.replace(/<i>(.*?)<\/i>/g, "_$1_")
  html = html.replace(/<s>(.*?)<\/s>/g, "~$1~")
  html = html.replace(/<\/?[a-z][a-z0-9]*\b[^>]*>/gi, "")    # strip remaining tags
  return html
```

## Text Chunking Per Platform

### Chunk Limits

| Channel   | Limit | Chunker Mode | Notes |
|-----------|-------|-------------|-------|
| Telegram  | 4096  | markdown    | Respects fence blocks, converts to Telegram HTML |
| Discord   | 2000  | none        | API enforces; delivered as-is |
| Slack     | 4000  | none        | API enforces; delivered as-is |
| WhatsApp  | 4000  | text        | Blind length-based split |
| Signal    | 4000  | text        | Blind length-based split |
| iMessage  | 4000  | text        | Blind length-based split |
| IRC       | 350   | text        | Short limit, fence-aware |
| Default   | 4000  | varies      | Fallback for unmapped channels |

### Algorithm 1: Length-Based (chunkText)

Simplest splitter — just cuts at the limit:

```
chunkText(text, limit):
  if (text.length <= limit): return [text]

  chunks = []
  remaining = text
  while (remaining.length > 0):
    chunk = remaining.substring(0, limit)
    chunks.push(chunk)
    remaining = remaining.substring(limit)

  return chunks
```

### Algorithm 2: Paragraph-Aware (chunkByParagraph)

Splits on blank lines, respects code blocks:

```
chunkByParagraph(text, limit, opts):
  # 1. Parse fence spans (``` code blocks, > quotes)
  spans = parseFenceSpans(text)

  # 2. Split on blank lines (\n[\t ]*\n+)
  #    BUT skip splits inside fenced blocks
  parts = []
  for boundary in findBlankLines(text):
    if (not insideFenceSpan(boundary, spans)):
      parts.push(textBetween(lastBoundary, boundary))

  # 3. Accumulate parts into chunks
  chunks = []
  currentChunk = ""
  for part in parts:
    if (currentChunk.length + part.length <= limit):
      currentChunk += part
    else:
      if (currentChunk): chunks.push(currentChunk)
      if (part.length <= limit):
        currentChunk = part
      else if (opts.splitLongParagraphs):
        chunks.push(...chunkText(part, limit))    # fallback to blind split
        currentChunk = ""
      else:
        chunks.push(part)                          # keep intact even if over limit
        currentChunk = ""

  if (currentChunk): chunks.push(currentChunk)
  return chunks
```

### Algorithm 3: Markdown-Aware (chunkMarkdownText)

```
chunkMarkdownTextWithMode(text, limit, mode):
  if (mode === "newline"):
    # Paragraph chunking preserves fence safety
    paragraphs = chunkByParagraph(text, limit, { splitLongParagraphs: false })
    chunks = []
    for paragraph in paragraphs:
      nested = chunkMarkdownText(paragraph, limit)    # further split if needed
      chunks.push(...nested)
    return chunks
  else:
    return chunkMarkdownText(text, limit)
```

### Chunk Limit Resolution

```
resolveTextChunkLimit(cfg, provider, accountId, opts):
  # Config hierarchy:
  # 1. Account-specific override
  accountLimit = cfg.channels[provider].accounts[accountId].textChunkLimit
  if (accountLimit): return accountLimit

  # 2. Provider-wide setting
  providerLimit = cfg.channels[provider].textChunkLimit
  if (providerLimit): return providerLimit

  # 3. Fallback default
  return 4000
```

## Adapter Pattern

### Plugin Registration & Loading

```
createChannelRegistryLoader(resolveValue):
  cache = Map()
  lastRegistry = null

  return async (channelId) => {
    registry = getActivePluginRegistry()

    # Invalidate cache when registry changes
    if (registry !== lastRegistry):
      cache.clear()
      lastRegistry = registry

    # Lookup from cache or resolve
    if (cache.has(channelId)): return cache.get(channelId)

    entry = registry.channels.find(e => e.plugin.id === channelId)
    if (not entry): return undefined

    value = resolveValue(entry)
    cache.set(channelId, value)
    return value
  }
```

### Outbound Handler Creation

```
createChannelHandler(params):
  outbound = await loadChannelOutboundAdapter(params.channel)

  return {
    chunker: outbound.chunker ?? null,
    textChunkLimit: outbound.textChunkLimit,
    supportsMedia: Boolean(outbound.sendMedia),

    sendText: async (text, overrides) =>
      await outbound.sendText({
        ...baseCtx,
        text,
        replyToId: overrides?.replyToId ?? baseCtx.replyToId,
        threadId: overrides?.threadId ?? baseCtx.threadId,
      }),

    sendMedia: async (caption, mediaUrl, overrides) =>
      outbound.sendMedia
        ? await outbound.sendMedia({ ...ctx, text: caption, mediaUrl })
        : await outbound.sendText({ ...ctx, text: caption })
  }
```

### Payload Type Dispatch

```
sendTextMediaPayload(adapter, ctx):
  text = ctx.payload.text ?? ""
  urls = ctx.payload.mediaUrls?.length
    ? ctx.payload.mediaUrls
    : ctx.payload.mediaUrl ? [ctx.payload.mediaUrl] : []

  if (urls.length > 0):
    for url in urls:
      lastResult = await adapter.sendMedia({ ...ctx, mediaUrl: url })
    return lastResult

  # Text only — chunk if needed
  chunks = adapter.chunker
    ? adapter.chunker(text, adapter.textChunkLimit)
    : [text]

  for chunk in chunks:
    lastResult = await adapter.sendText({ ...ctx, text: chunk })
  return lastResult
```

## Channel Lifecycle

### State Machine

```
                    ┌─────────────┐
                    │ INITIALIZED │
                    └──────┬──────┘
                           │
                    Check enabled?
                    ├─ NO → DISABLED
                    │
                    Check configured?
                    ├─ NO → NOT_CONFIGURED
                    │
                    ▼
                ┌─────────┐
                │ RUNNING  │ ← reconnectAttempts = 0
                └────┬────┘
                     │
              startAccount()
              ├─ Success ──→ CONNECTED (running=true)
              └─ Error ────→ STOPPED (running=false, lastError set)
                               │
                        Auto-restart?
                        ├─ manuallyStopped → NO
                        ├─ attempts > 10 → ABANDONED
                        └─ YES → backoff delay → retry startAccount()

Backoff policy:
  initialMs: 5000
  maxMs: 300000 (5 min)
  factor: 2
  jitter: 0.1
```

### Health Check Cycle

```
INTERVAL = 5 minutes
STARTUP_GRACE = 60 seconds
CONNECT_GRACE = 120 seconds
STALE_THRESHOLD = 30 minutes
COOLDOWN = 2 cycles (10 min between restarts)
MAX_RESTARTS = 10 per hour

every INTERVAL:
  for account in allChannelAccounts:
    if (now - startedAt < STARTUP_GRACE): skip

    health = evaluateChannelHealth(account)

    if (health.healthy): continue
    if (now - lastRestart <= COOLDOWN): skip
    if (restartsThisHour >= MAX_RESTARTS): log warning, skip

    # Trigger restart
    await channelManager.stop(account)
    channelManager.resetRestartAttempts(account)
    await channelManager.start(account)
    recordRestartTimestamp()
```

### Health Evaluation Rules

```
evaluateChannelHealth(status):
  if (not managed): return healthy (unmanaged)
  if (not running): return unhealthy ("not-running")

  if (busy and activeRuns > 0):
    if (runActivityAge < 25 min): return healthy ("busy")
    else: return unhealthy ("stuck")

  if (within startup grace < 120s): return healthy ("startup-grace")
  if (connected === false): return unhealthy ("disconnected")

  # Socket staleness (except Telegram and webhooks)
  if (channelId !== "telegram" and mode !== "webhook"):
    if (eventAge > 30 min): return unhealthy ("stale-socket")

  return healthy
```

## Outbound Delivery Queue

### Write-Ahead Queue

```
Location: ~/.openclaw/state/delivery-queue/

Files:
  {id}.json           # Queued delivery record (atomic write)
  {id}.delivered       # Marks completed delivery (two-phase ack)
  failed/              # Failed deliveries after max retries
```

### Retry Backoff

```
Attempt 1: 5 seconds
Attempt 2: 25 seconds (5 × 5)
Attempt 3: 2 minutes (25 × 5)
Attempt 4: 10 minutes (2m × 5)
After 4:   give up
MAX_RETRIES = 5
```

### Two-Phase Acknowledgment

```
Phase 1: Rename {id}.json → {id}.delivered
  Atomic: marks delivery as "in flight"
  If process dies here, next recovery doesn't resend

Phase 2: Unlink {id}.delivered
  Cleanup after confirmed success

Recovery on startup:
  for each {id}.json in queue:
    if ({id}.delivered exists):
      delete {id}.delivered       # crashed after delivery
      continue                    # don't resend

    if (retryCount < MAX_RETRIES):
      if (now - lastAttempt >= backoff[retryCount]):
        retry delivery
    else:
      move to failed/ directory
```

### Delivery Context

```
ChannelOutboundContext = {
  cfg: OpenClawConfig,
  to: string,                       # destination ID
  text: string,                     # message body
  mediaUrl?: string,                # single media URL
  mediaLocalRoots?: string[],       # for local file resolution
  replyToId?: string,               # reply/thread context
  threadId?: string | number,       # thread/group context
  accountId?: string,               # which bot account to use
  identity?: OutboundIdentity,      # sender identity override
  silent?: boolean,                 # suppress notifications
  gifPlayback?: boolean,            # animated GIF handling
}
```

### Delivery Result

```
OutboundDeliveryResult = {
  channel: string,                  # "slack", "discord", etc.
  messageId: string,                # platform message ID
  chatId?: string,                  # group/channel ID
  timestamp?: number,               # delivery time
  roomId?: string,                  # Matrix-specific
  conversationId?: string,          # Teams-specific
  toJid?: string,                   # XMPP Jabber ID
  pollId?: string,                  # poll result ID
  meta?: Record<string, unknown>,   # platform-specific
}
```

### Complete Send Flow

```
sendMessage(agentId, to, text):
  cfg = loadConfig()

  # 1. Route resolution
  route = resolveRoute(agentId, channel)

  # 2. Target normalization
  normalized = normalizeOutboundTarget(to)

  # 3. Load channel adapter
  adapter = await loadChannelOutboundAdapter(channel)

  # 4. Text chunking
  chunks = adapter.chunker
    ? adapter.chunker(text, adapter.textChunkLimit)
    : [text]

  # 5. Delivery loop with retry
  for chunk in chunks:
    try:
      result = await adapter.sendText({
        cfg, to: normalized, text: chunk,
        accountId, replyToId, threadId
      })
      ackDelivery(deliveryId)           # two-phase commit
    catch:
      enqueueForRetry(delivery, error)  # backoff: 5s, 25s, 2m, 10m

  return lastResult
```
