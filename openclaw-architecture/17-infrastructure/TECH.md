# Infrastructure — Technical Implementation Details

## Path Validation Algorithm

### Dual-Cursor Traversal

The path boundary system uses two cursors that advance together segment-by-segment:

- **lexicalCursor**: Follows the path as typed by the user
- **canonicalCursor**: Resolves symlinks at every step

```
Input: /workspace/docs/../secrets/../../etc/passwd
Root:  /workspace

Step 1: segment="docs"
  lexical:   /workspace/docs
  canonical: /workspace/docs (not a symlink, same)

Step 2: segment=".."
  lexical:   /workspace
  canonical: /workspace

Step 3: segment="secrets"
  lexical:   /workspace/secrets
  canonical: /workspace/secrets

Step 4: segment=".."
  lexical:   /workspace          ← still looks inside root
  canonical: /workspace          ← canonical also inside root

Step 5: segment=".."
  lexical:   /                   ← ESCAPED ROOT
  canonical: /                   ← BOUNDARY CHECK FAILS → throw pathEscapeError
```

### Symlink Resolution per Segment

For each segment, the system calls `lstat()` to check if it's a symlink:

```
If symlink AND not final segment:
  1. realpath() → get absolute target
  2. Check: isPathInside(root, target)?
     - YES: Update canonicalCursor to target, continue
     - NO:  throw symlinkEscapeError

If symlink AND final segment AND allowFinalSymlinkForUnlink:
  → Preserve symlink (allow deleting the link itself)

If not a symlink:
  → Advance both cursors normally
```

### isPathInside Check

```
isPathInside(root, target):
  relative = path.relative(root, target)
  return !relative.startsWith("..") && !path.isAbsolute(relative)
```

### Ancestor Walk for Broken Symlinks

When `realpath()` fails on a broken symlink:

```
resolvePathViaExistingAncestor("/workspace/link-to-nowhere/file.txt"):
  1. Try: realpath("/workspace/link-to-nowhere/file.txt") → ENOENT
  2. Walk up: realpath("/workspace/link-to-nowhere") → ENOENT
  3. Walk up: realpath("/workspace") → "/workspace" (exists!)
  4. Return: "/workspace" + "/link-to-nowhere/file.txt" = resolved path
```

## Retry System

### Exponential Backoff Formula

```
Given: attempt (1-based), minDelayMs, maxDelayMs, jitter (0-1)

Step 1: Base delay
  baseDelay = minDelayMs × 2^(attempt - 1)

  Example with minDelayMs=300:
    attempt 1: 300 × 2^0 = 300ms
    attempt 2: 300 × 2^1 = 600ms
    attempt 3: 300 × 2^2 = 1200ms
    attempt 4: 300 × 2^3 = 2400ms

Step 2: Cap at maximum
  delay = min(baseDelay, maxDelayMs)

Step 3: Apply jitter (symmetric)
  offset = random(-1, +1) × jitter
  delay = delay × (1 + offset)
  delay = max(0, round(delay))

  Example with jitter=0.2, delay=600:
    offset range: [-0.2, +0.2]
    delay range: [480, 720]

Step 4: Final clamp
  delay = clamp(delay, minDelayMs, maxDelayMs)
```

### Retry-After Support

When a provider returns a `Retry-After` header:

```
If retryAfterMs is provided:
  baseDelay = max(retryAfterMs, minDelayMs)
  // Skip exponential calculation, use server's suggestion
  // Still apply jitter and cap
```

### Provider-Specific Retry Policies

**Telegram:**
```
attempts: 3
minDelayMs: 400
maxDelayMs: 30000
jitter: 0.1
shouldRetry: matches /429|timeout|connect|reset|closed|unavailable|temporarily/i
retryAfterMs: extracted from err.parameters.retry_after (seconds → ms)
```

**Discord:**
```
attempts: 3
minDelayMs: 500
maxDelayMs: 30000
jitter: 0.1
shouldRetry: err instanceof RateLimitError
retryAfterMs: err.retryAfter × 1000
```

## Rate Limiting

### Fixed-Window Algorithm

This is the simplest rate limiter — a counter that resets on a fixed schedule:

```
State:
  count = 0              # requests in current window
  windowStart = 0        # when this window began

consume():
  now = Date.now()

  # Check if window expired
  if (now - windowStart) >= windowMs:
    windowStart = now    # start new window
    count = 0            # reset counter

  # Check if over limit
  if count >= maxRequests:
    return {
      allowed: false,
      retryAfterMs: windowStart + windowMs - now,  # time until window resets
      remaining: 0
    }

  # Allow request
  count += 1
  return {
    allowed: true,
    retryAfterMs: 0,
    remaining: maxRequests - count
  }
```

**Space complexity**: O(1) — just two numbers.
**Time complexity**: O(1) — one comparison per call.

No background cleanup needed. The window resets lazily on the next call.

## HTTP Body Size Enforcement

### Two-Phase Protection

**Phase 1: Content-Length check (instant reject)**
```
contentLength = parseContentLength(req.headers["content-length"])
if contentLength > maxBytes:
  req.destroy()
  throw PAYLOAD_TOO_LARGE (413)
```

**Phase 2: Streaming accumulation (catch liars)**
```
totalBytes = 0
chunks = []
timeout = setTimeout(→ throw REQUEST_BODY_TIMEOUT, timeoutMs)

req.on("data", chunk):
  totalBytes += chunk.length
  if totalBytes > maxBytes:
    req.destroy()
    throw PAYLOAD_TOO_LARGE (413)
  chunks.push(chunk)

req.on("end"):
  clearTimeout(timeout)
  body = Buffer.concat(chunks).toString("utf-8")
  return body
```

Phase 1 catches honest clients immediately. Phase 2 catches clients that lie about Content-Length or send chunked-encoding without a length header.

## Outbound Delivery Pipeline

### Complete Flow

```
1. ENQUEUE (write-ahead)
   └─ Save payloads to delivery queue (crash recovery)

2. NORMALIZE per channel
   ├─ Strip HTML for plain-text channels
   ├─ Normalize whitespace per platform
   └─ Filter empty payloads

3. FOR EACH payload:
   ├─ Run message_sending hook (can cancel or modify)
   ├─ Determine delivery mode:
   │   ├─ Channel-specific data → sendPayload()
   │   ├─ Text only → chunk and sendText()
   │   └─ Has media → sendMedia() with caption
   ├─ CHUNK if text > limit:
   │   ├─ Telegram: 4096 chars, paragraph-aware
   │   ├─ Discord: 2000 chars, code-block-aware
   │   ├─ IRC: 350 chars, fence-aware
   │   └─ Signal: markdown-to-signal conversion
   ├─ SEND via channel plugin
   └─ Run message_sent hook

4. CLEANUP queue
   ├─ Success → ackDelivery(queueId)
   ├─ Partial failure (bestEffort) → failDelivery(queueId)
   └─ Abort → ackDelivery (treat as done)
```

## Process Restart State Machine

### SIGUSR1 Token System

The restart system uses a token-based authorization pattern to prevent accidental restarts:

```
State:
  authorizedCount = 0        # available restart tokens
  authorizedUntil = 0        # token expiration timestamp
  restartCycleToken = 0      # monotonic counter
  lastRestartAt = 0          # cooldown tracking

authorize(delayMs):
  authorizedCount += 1
  authorizedUntil = max(authorizedUntil, now + delayMs + 5000ms grace)

consume():
  if now > authorizedUntil:
    authorizedCount = 0      # tokens expired
    return false
  if authorizedCount > 0:
    authorizedCount -= 1
    return true
  return false
```

### Restart with Pending Work Deferral

```
scheduleRestart(delayMs):
  1. Apply cooldown: effectiveDelay = max(delayMs, lastRestart + 30s - now)
  2. Set timer for effectiveDelay
  3. When timer fires:
     a. If preRestartCheck callback exists:
        - Call getPendingCount()
        - If 0: restart immediately
        - If > 0: poll every 500ms for up to 30s
        - After 30s: restart anyway (timeout)
     b. Else: restart immediately
  4. Restart = process.kill(process.pid, "SIGUSR1")
```

### Platform-Specific Restart

```
macOS (launchd):
  launchctl kickstart -k gui/{uid}/{label}
  Fallback: bootstrap from plist, then retry kickstart

Linux (systemd):
  systemctl --user restart {unit}
  Fallback: systemctl restart {unit} (system-level)

Windows (schtasks):
  relaunchGatewayScheduledTask(process.env)

Fallback (detached spawn):
  spawn(process.execPath, [...args], { detached: true, stdio: "inherit" }).unref()
```

## Error Classification

### Error Graph Traversal

Errors can be nested (cause chains). The system uses BFS to find all related errors:

```
collectErrorGraphCandidates(err):
  queue = [err]
  seen = Set()
  candidates = []

  while queue not empty:
    current = queue.shift()
    if current is null or seen.has(current): skip
    seen.add(current)
    candidates.push(current)

    # Check for nested errors:
    if current.cause: queue.push(current.cause)
    if current.errors: queue.push(...current.errors)  # AggregateError
    if resolveNested: queue.push(...resolveNested(current))

  return candidates
```

This prevents infinite loops via the `seen` Set, even if errors have circular references.

### Error Message Formatting

```
formatErrorMessage(err):
  if err instanceof Error:
    return redactSensitiveText(err.message || err.name || "Error")
  if typeof err === "string":
    return redactSensitiveText(err)
  if typeof err === "number" or "boolean" or "bigint":
    return String(err)
  try:
    return JSON.stringify(err)
  catch:
    return String(err)
```

Sensitive text redaction strips API keys matching patterns like `sk-ant-*`, `xoxb-*`, etc.
