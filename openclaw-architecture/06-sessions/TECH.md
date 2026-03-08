# Sessions — Technical Implementation Details

## JSONL Transcript Format

### Header Line (First Line)

Every transcript file begins with a session header:

```json
{"type":"session","version":5,"id":"<uuid>","timestamp":"2026-03-08T12:00:00Z","cwd":"/workspace","parentSession":"/path/to/parent.jsonl"}
```

- `version`: Current session format version (incremented on schema changes)
- `parentSession`: Only present for forked/branched sessions
- `cwd`: Working directory when session was created

### Message Lines

Each subsequent line is one message:

```json
{"type":"message","message":{"role":"user","content":[{"type":"text","text":"Hello"}],"timestamp":1709904000000}}
{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"Hi!"}],"model":"claude-opus-4-6","usage":{"input":50,"output":5,"cacheRead":0,"cacheWrite":0,"totalTokens":55},"stopReason":"stop"}}
```

Fields per message:
- `role`: "user", "assistant", or "toolResult"
- `content`: Array of content blocks (text, image, tool_use, tool_result)
- `timestamp`: Epoch milliseconds
- `model`: LLM model used (assistant only)
- `usage`: Token counts and costs (assistant only)
- `stopReason`: Why generation stopped (assistant only)
- `api`: API protocol used ("openai-responses", etc.)
- `provider`: Provider identifier

### Append Mechanics

```
appendMessage(filePath, record):
  line = JSON.stringify(record) + "\n"

  # Queue-based serialization:
  queue = queue
    .then(() => ready)                   # wait for directory creation
    .then(() => fs.appendFile(filePath, line, "utf-8"))
    .catch(() => undefined)              # silent failure (best-effort)
```

The promise chain ensures writes are serialized — even when multiple async operations try to append simultaneously. Each `appendFile` call is atomic at the OS level for writes under the pipe buffer size (typically 4-64 KB).

### Reading Back

```
readTranscript(filePath):
  raw = fs.readFileSync(filePath, "utf-8")
  lines = raw.split("\n")
  messages = []

  for line in lines:
    if (line is empty): skip
    parsed = JSON.parse(line)
    if (parsed.type === "message"):
      messages.push(parsed.message)

  return messages
```

### File Permissions

- Session files created with mode `0o600` (read/write owner only)
- Parent directories created with mode `0o700` (owner only)

## Session Store (sessions.json)

### Entry Structure

The session store is a JSON file mapping normalized keys to entries:

```
{
  "agent:main:telegram:12345": {
    "sessionId": "uuid-here",
    "sessionFile": "/path/to/sessions/uuid.jsonl",
    "updatedAt": 1709904000000,
    "channel": "telegram",
    "deliveryContext": {
      "channel": "telegram",
      "to": "12345",
      "accountId": "bot-account",
      "threadId": null
    },
    "label": "User Chat",
    "displayName": "John",
    "origin": {
      "provider": "telegram",
      "surface": "private",
      "chatType": "dm",
      "from": "user-id",
      "to": "bot-id",
      "threadId": null
    },
    "modelOverride": null,
    "compactionCount": 2,
    "totalTokens": 15000,
    "totalTokensFresh": true,
    "acp": {
      "agent": "main",
      "mode": "conversation",
      "state": "idle",
      "lastActivityAt": 1709904000000
    },
    "spawnedBy": null,
    "forkedFromParent": false
  }
}
```

### Key Normalization

```
resolveSessionStoreEntry({ store, sessionKey }):
  normalized = sessionKey.trim().toLowerCase()

  # Find existing entry (case-insensitive)
  existing = store[normalized]
  legacyKeys = []

  # Check for case variants (legacy data)
  for key in Object.keys(store):
    if (key.toLowerCase() === normalized and key !== normalized):
      legacyKeys.push(key)
      if (not existing or store[key].updatedAt > existing.updatedAt):
        existing = store[key]    # use most recently updated variant

  return { normalizedKey: normalized, existing, legacyKeys }
```

### Caching

```
Read path:
  1. Check in-memory cache for storePath
  2. If found AND ttl(45s) not expired AND mtime matches AND size matches:
     return structuredClone(cached.store)     # deep copy prevents mutation
  3. Cache miss: read from disk, parse JSON, cache result

Write path:
  1. Acquire per-store lock (async mutex)
  2. Read current store from cache or disk
  3. Apply mutations
  4. Write atomically (temp file + rename)
  5. Update cache with new data + new mtime/size
  6. Release lock
```

`structuredClone` on every read prevents callers from accidentally mutating the cached data.

## Session Lifecycle

### Creation

```
1. First inbound message arrives
2. Generate sessionId = UUIDv4
3. Resolve file path:
   sessionFile = {agentDir}/sessions/{sessionId}.jsonl
4. Write session header as first JSONL line
5. Create entry in sessions.json store
6. Record delivery context (channel, to, threadId)
```

### Updates

Each turn updates the session entry:

```
recordSessionMetaFromInbound(entry, inbound):
  entry.updatedAt = Date.now()
  entry.channel = inbound.channel
  entry.deliveryContext = {
    channel: inbound.channel,
    to: inbound.to,
    accountId: inbound.accountId,
    threadId: inbound.threadId
  }

# All updates within lock:
withSessionStoreLock(storePath, async () => {
  store = readStore()
  mutate(store)
  writeStoreAtomic(store)
})
```

### Freshness Evaluation

```
isSessionTotalTokensFresh(entry):
  if (entry.totalTokensFresh === false): return false    # explicitly stale
  if (entry.totalTokens is valid number): return true    # fresh
  return false                                            # unknown/legacy
```

## Compaction Algorithm

### When Compaction Triggers

Compaction runs when the context window approaches capacity during an agent run.

### Token Estimation

```
estimateMessagesTokens(messages):
  # Heuristic: 4 characters ≈ 1 token
  totalChars = sum(JSON.stringify(msg).length for msg in messages)
  rawTokens = totalChars / 4

  # Safety margin: 1.2x to compensate for multi-byte chars
  return Math.ceil(rawTokens * 1.2)
```

### Message Chunking

```
chunkMessagesByMaxTokens(messages, maxTokens):
  effectiveMax = maxTokens / 1.2          # remove safety margin for internal use
  chunks = []
  currentChunk = []
  currentTokens = 0

  for msg in messages:
    msgTokens = estimateTokens(msg)
    if (currentTokens + msgTokens > effectiveMax and currentChunk.length > 0):
      chunks.push(currentChunk)
      currentChunk = []
      currentTokens = 0
    currentChunk.push(msg)
    currentTokens += msgTokens

  if (currentChunk.length > 0):
    chunks.push(currentChunk)

  return chunks
```

### 3-Tier Summarization Strategy

```
Tier 1: FULL SUMMARIZATION (default)
  1. Split all messages into chunks of SUMMARIZATION_OVERHEAD_TOKENS (4096)
  2. For each chunk, call generateSummary(chunk)
  3. If multiple chunks, merge summaries into one

  Summary prompt preserves:
    - Active tasks and progress (e.g., "5/17 items completed")
    - Decisions made and rationale
    - Last user request and current action
    - TODOs, open questions, constraints
    - All opaque identifiers exactly (UUIDs, hashes, file paths, IPs)

Tier 2: PARTIAL SUMMARIZATION (fallback if Tier 1 fails)
  1. Only summarize messages < 50% of context window
  2. For oversized messages: "[Large message (~XXK tokens) omitted]"
  3. Allows agent to continue with partial history

Tier 3: MINIMAL FALLBACK (if summarization fails entirely)
  1. Generate: "Context contained N messages (X oversized)"
  2. Agent starts fresh with minimal context
```

### Tool Result Stripping

Before sending messages to the LLM for summarization:

```
stripToolResultDetails(messages):
  for msg in messages:
    if (msg has toolResult.details):
      remove details            # security: untrusted/verbose payloads
  return messages
```

## Context Pruning

### Two-Stage Trimming

Context pruning is opt-in via `session.contextPruning.mode: "cache-ttl"`.

```
Stage 1: SOFT TRIM (shrink large tool results)
  For each tool result > softTrim.maxChars (4000):
    Keep first headChars (1500)
    Keep last tailChars (1500)
    Insert "... [trimmed] ..." between

  Skips: image tool results (important context)

Stage 2: HARD CLEAR (when soft trim is insufficient)
  Triggered if: context still > hardClearRatio (0.5) of window after Stage 1

  For each tool result with >= minPrunableToolChars (50K chars):
    Replace entire content with: "[Old tool result content cleared]"
    Keep tool name and ID for reference
```

### Freshness TTL

```
Pruning frequency control:
  lastCacheTouchAt = timestamp of last prune
  ttlMs = 5 minutes

  if (now - lastCacheTouchAt < ttlMs):
    skip pruning    # prevent churn; let agent consume context
```

### Protected Content

```
NEVER pruned:
  - Last N assistant messages (keepLastAssistants = 3)
  - All messages before first user message (bootstrap context: SOUL.md, USER.md)
```

## Thread/Topic Sessions

### Session Key Format

```
Base key:       {channel}:{to}
Thread suffix:  :thread:{threadId}    (Discord, Slack, WhatsApp)
Topic suffix:   :topic:{topicId}      (Telegram)

Examples:
  telegram:12345                       # DM session
  telegram:12345:topic:789             # Topic thread in Telegram group
  discord:guild:channel:thread:abc     # Discord thread
```

### Parsing

```
parseSessionThreadInfo(sessionKey):
  # Split on rightmost :thread: or :topic:
  markers = [":thread:", ":topic:"]
  for marker in markers:
    idx = sessionKey.lastIndexOf(marker)
    if (idx >= 0):
      baseKey = sessionKey.substring(0, idx)
      threadId = sessionKey.substring(idx + marker.length).trim()
      return { baseKey, threadId, marker }

  return { baseKey: sessionKey, threadId: null, marker: null }
```

### Forking from Parent

When a thread session is created for the first time:

```
forkSessionFromParent(parentEntry):
  1. Load parent's SessionManager from parentEntry.sessionFile
  2. Create branched session:
     - New UUID sessionId
     - New file: {timestamp}_{uuid}.jsonl
     - Header includes: "parentSession": parentFile
  3. Copy parent transcript into new file (inherits context)
  4. Mark entry: forkedFromParent = true (prevents re-copying)

  Guard: parentForkMaxTokens (100K default)
    If parent context > 100K tokens, skip forking (too large)
```

## Session Maintenance

### Stale Detection

```
pruneStaleEntries(store, maxAgeMs):
  cutoffMs = Date.now() - maxAgeMs          # default: 30 days

  for key in Object.keys(store):
    entry = store[key]
    if (entry.updatedAt and entry.updatedAt < cutoffMs):
      delete store[key]
    # Entries without updatedAt: kept (can't determine age)
```

### Entry Cap

```
capEntryCount(store, maxEntries):
  entries = Object.entries(store)

  # Sort by updatedAt descending (most recent first)
  # Entries without updatedAt sort last (removed first)
  entries.sort((a, b) => (b.updatedAt ?? 0) - (a.updatedAt ?? 0))

  # Keep top N, delete rest
  for i from maxEntries to entries.length:
    delete store[entries[i].key]

  # Default max: 500 entries
```

### Disk Budget Enforcement

```
enforceSessionDiskBudget(params):
  totalBytes = sum(size of all session files + store file)

  if (totalBytes > maxDiskBytes):
    # Phase 1: Delete archived/orphaned files (oldest mtime first)
    orphans = findOrphanedTranscripts()
    for file in orphans sorted by mtime ascending:
      delete file
      totalBytes -= file.size
      if (totalBytes <= highWaterBytes): break

    # Phase 2: Remove stale entries (if still over budget)
    if (totalBytes > highWaterBytes):
      for entry in store sorted by updatedAt ascending:
        if (entry === activeSession): skip    # never remove current
        refCount = countReferencesToSessionId(entry.sessionId)
        delete store[entry.key]
        if (refCount === 0):
          delete entry.sessionFile            # safe to remove file
        totalBytes -= savedBytes
        if (totalBytes <= highWaterBytes): break
```

### File Rotation

```
When sessions.json > rotateBytes (10 MB):
  1. Rename to sessions.json.bak.{timestamp}
  2. Keep 3 most recent backups
  3. Delete older backups

Archive naming:
  {sessionId}.jsonl.{reason}.{ISO-timestamp}
  Reasons: "deleted", "reset", "bak"
  Cleaned up after resetArchiveRetentionMs (default: same as pruneAfterMs)
```

### Maintenance Modes

```
"warn" (default):
  - Log warnings about stale sessions
  - Don't prune active sessions

"enforce":
  - Prune stale entries
  - Cap entry count
  - Rotate oversized files
  - Archive removed transcripts
  - Enforce disk budget
```

## Concurrency & Locking

### Session Store Lock

```
withSessionStoreLock(storePath, fn):
  1. Acquire file-level lock via acquireSessionWriteLock()
  2. Lock stale timeout: 30 seconds
  3. Queue-based: pending tasks wait if lock held
  4. Task timeout: 10 seconds default
  5. Execute fn()
  6. Release lock in finally block

  Windows: 5 retry attempts with 50ms backoff on write failures
```

### File Lock Details

See [18-storage/TECH.md](../18-storage/TECH.md) for the complete write-lock algorithm with PID staleness detection, watchdog timer, and process exit cleanup.
