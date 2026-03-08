# Storage — Technical Implementation Details

## Atomic Write Pattern

Every important file write in OpenClaw follows this exact sequence:

```
writeTextAtomic(filePath, content):
  1. Generate temp name: "{filePath}.{randomUUID()}.tmp"
     Example: "sessions.json.a3f2b1c4-5d6e-7f8a-9b0c-1d2e3f4a5b6c.tmp"

  2. Create parent directory:
     mkdir(dirname(filePath), { recursive: true, mode: 0o700 })

  3. Write to temp file:
     writeFile(tmpPath, content, "utf-8")

  4. Set permissions:
     chmod(tmpPath, 0o600)    // owner read/write only

  5. Atomic rename:
     rename(tmpPath, filePath)  // POSIX: atomic inode swap

  6. Cleanup (in finally block):
     rm(tmpPath, { force: true })  // remove temp if rename failed
```

**Why this works**: On POSIX systems, `rename()` is an atomic operation. At any point in time, readers see either the complete old file or the complete new file — never a partial write. If the process crashes during step 3, only the temp file is corrupted; the original is untouched.

**UUID in temp name**: Prevents collisions when multiple processes write simultaneously. Each gets its own temp file.

## JSONL Transcript Format

### Byte-Level Format

```
Line 1 (header):   {"type":"session","version":5,"id":"uuid","timestamp":"ISO8601","cwd":"/path"}\n
Line 2 (message):  {"type":"message","message":{"role":"user","content":[{"type":"text","text":"Hello"}]}}\n
Line 3 (message):  {"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"Hi!"}],"model":"claude-opus-4-6","usage":{"input":50,"output":5}}}\n
...
```

Each line is:
- A complete, self-contained JSON object
- Terminated by a single `\n` character
- No trailing comma, no array wrapper, no enclosing braces

### Append Operation

```
appendMessage(filePath, record):
  line = JSON.stringify(record) + "\n"

  # Queue-based serialization (one write at a time):
  queue = queue
    .then(() => ready)              # wait for directory creation
    .then(() => fs.appendFile(filePath, line, "utf-8"))
    .catch(() => undefined)          # silent failure (best-effort)
```

The promise chain ensures writes are serialized even when multiple async operations try to append simultaneously. Each `appendFile` call is atomic at the OS level for small writes (under the pipe buffer size, typically 4KB-64KB).

### Reading Back

```
readTranscript(filePath):
  raw = fs.readFileSync(filePath, "utf-8")
  lines = raw.split("\n")
  messages = []

  for line in lines:
    if line is empty: skip
    parsed = JSON.parse(line)
    if parsed.type === "message":
      messages.push(parsed.message)

  return messages
```

## Write-Lock Algorithm

### Lock File Format

```json
{
  "pid": 12345,
  "createdAt": "2026-03-08T10:30:45.123Z",
  "starttime": 54321
}
```

- `pid`: Process ID that holds the lock
- `createdAt`: ISO timestamp when lock was acquired
- `starttime`: Process start time (from `/proc/{pid}/stat` on Linux, `ps` on macOS)

The `starttime` field detects **PID recycling** — when the OS reuses a PID for a new process after the original dies.

### Acquisition Algorithm (Step by Step)

```
acquireLock(sessionFile, timeoutMs=10000, staleMs=1800000):
  lockPath = sessionFile + ".lock"
  normalized = realpath(sessionFile) or resolve(sessionFile)

  # Step 1: Check reentrant lock
  if HELD_LOCKS.has(normalized):
    held = HELD_LOCKS.get(normalized)
    held.count += 1          # increment reentrant count
    return held.release      # return same release function

  # Step 2: Acquisition loop
  deadline = now() + timeoutMs
  attempt = 0

  while now() < deadline:
    attempt += 1

    try:
      # Exclusive create (fails if file exists)
      handle = fs.open(lockPath, "wx")

      # Write lock payload
      payload = { pid: process.pid, createdAt: new Date().toISOString(), starttime: getProcessStartTime(process.pid) }
      fs.write(handle, JSON.stringify(payload))

      # Register in held locks map
      HELD_LOCKS.set(normalized, { handle, count: 1, path: lockPath, acquiredAt: now() })

      return releaseFn     # success!

    catch (err):
      if err.code !== "EEXIST": throw err    # unexpected error

      # Lock file exists — check if stale
      existingPayload = readLockPayload(lockPath)
      inspection = inspectStaleness(existingPayload, staleMs)

      if inspection.stale:
        fs.rm(lockPath, { force: true })     # remove stale lock
        continue                              # retry immediately

      # Not stale — wait and retry
      delay = min(1000, 50 × attempt)        # up to 1 second
      await sleep(delay)

  throw Error("Lock acquisition timeout after " + timeoutMs + "ms")
```

### Staleness Detection Logic

```
inspectStaleness(payload, staleMs):
  reasons = []

  # Check 1: PID present?
  if payload.pid is null:
    reasons.push("missing-pid")

  # Check 2: Process alive?
  else if not isPidAlive(payload.pid):
    reasons.push("dead-pid")

  # Check 3: PID recycled?
  else if getProcessStartTime(payload.pid) !== payload.starttime:
    reasons.push("recycled-pid")

  # Check 4: Valid timestamp?
  if not Date.parse(payload.createdAt):
    reasons.push("invalid-createdAt")

  # Check 5: Age check
  age = now() - Date.parse(payload.createdAt)
  if age > staleMs:                          # default: 30 minutes
    reasons.push("too-old")

  # Decision
  stale = reasons.length > 0

  # Extra check: if only reason is missing-pid or invalid-createdAt,
  # also check file mtime as fallback
  if reasons only contain "missing-pid" or "invalid-createdAt":
    fileMtime = fs.stat(lockPath).mtimeMs
    if (now() - fileMtime) > staleMs:
      stale = true
    else:
      stale = false    # file was recently touched, might be valid

  return { stale, reasons }
```

### PID Alive Check

```
isPidAlive(pid):
  try:
    process.kill(pid, 0)     # Signal 0 = check existence without killing
    return true
  catch:
    return false

getProcessStartTime(pid):
  # macOS:
  output = execSync("ps -o lstart= -p " + pid)
  return Date.parse(output.trim())

  # Linux:
  stat = fs.readFileSync("/proc/" + pid + "/stat", "utf-8")
  fields = stat.split(" ")
  return parseInt(fields[21])    # field 22 (0-indexed 21) is starttime in clock ticks
```

### Watchdog Timer

```
WATCHDOG_INTERVAL = 60_000     # 60 seconds

startWatchdog():
  setInterval(() => {
    for (normalized, held) of HELD_LOCKS:
      heldForMs = now() - held.acquiredAt
      if heldForMs > maxHoldMs:          # default: 5 minutes
        console.warn("Force-releasing lock held for " + heldForMs + "ms: " + held.path)
        releaseHeldLock(normalized, { force: true })
  }, WATCHDOG_INTERVAL)
```

### Release Function

```
release():
  held = HELD_LOCKS.get(normalized)
  if not held: return

  held.count -= 1

  if held.count > 0:
    return          # still held by reentrant caller

  # Actually release
  fs.close(held.handle)
  fs.rm(held.path, { force: true })
  HELD_LOCKS.delete(normalized)
```

### Process Exit Cleanup

```
process.on("exit", () => {
  for (normalized, held) of HELD_LOCKS:
    try:
      fs.closeSync(held.handle)
      fs.rmSync(held.path, { force: true })
    catch: ignore
  HELD_LOCKS.clear()
})

for signal in ["SIGINT", "SIGTERM", "SIGQUIT", "SIGABRT"]:
  process.on(signal, () => {
    releaseAllLocksSync()
    process.exit(128 + signalNumber)
  })
```

## Session Store Cache

### Cache Invalidation Strategy

```
Read path:
  1. Check in-memory cache for storePath
  2. If found AND ttl not expired AND mtime matches AND size matches:
     return structuredClone(cached.store)    # deep copy to prevent mutation
  3. If miss: read from disk, parse JSON, cache result

Write path:
  1. Acquire per-store lock (async mutex)
  2. Read current store from cache or disk
  3. Apply mutations
  4. Write atomically to disk
  5. Update cache with new data + new mtime/size
  6. Release lock

structuredClone: Used on every cache read to prevent callers from accidentally mutating the cached data.
```

### Windows Retry for Empty File Reads

```
readSessionStore(storePath):
  for attempt in [1, 2, 3]:
    raw = fs.readFileSync(storePath, "utf-8")
    if raw.length > 0:
      return JSON.parse(raw)

    # Windows: might see empty file during atomic write
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 50)    # sleep 50ms

  return {}    # give up, return empty store
```

## Secret Resolution Chain

### Resolution Order

```
resolveSecret(ref):
  switch ref.source:
    case "env":
      value = process.env[ref.id]
      if not value: throw MissingSecretError
      return value

    case "file":
      content = fs.readFile(ref.provider.path, "utf-8")
      if ref.provider.mode === "singleValue":
        return content.trim()
      else:
        parsed = JSON.parse(content)
        return jsonPointer(parsed, ref.id)    # e.g., "/path/to/key"

    case "exec":
      # Spawn process with JSON protocol
      input = JSON.stringify({
        protocolVersion: 1,
        provider: ref.provider,
        ids: [ref.id]
      })

      child = spawn(ref.provider.command, ref.provider.args)
      child.stdin.write(input)
      child.stdin.end()

      output = await readStdout(child, { timeout: 5000, maxBytes: 1MB })
      result = JSON.parse(output)

      if result.errors[ref.id]:
        throw SecretResolutionError(result.errors[ref.id])
      return result.values[ref.id]
```

### Batch Resolution

When multiple secrets share the same provider, they're batched:

```
resolveSecrets(refs):
  # Group by provider
  groups = groupBy(refs, r => r.source + ":" + r.provider)

  # Resolve each group (up to 4 providers concurrently)
  results = await parallelMap(groups, 4, async (group) => {
    if group.source === "exec":
      # Single exec call with all IDs
      input = { protocolVersion: 1, provider: group.provider, ids: group.map(r => r.id) }
      output = await execProvider(input)
      return output.values

    if group.source === "file":
      # Single file read, multiple JSON pointer lookups
      content = await readFile(group.provider.path)
      parsed = JSON.parse(content)
      return Object.fromEntries(group.map(r => [r.id, jsonPointer(parsed, r.id)]))

    if group.source === "env":
      return Object.fromEntries(group.map(r => [r.id, process.env[r.id]]))
  })

  return merge(results)
```

## Memory Database Schema

### Exact CREATE TABLE Statements

```sql
-- Metadata store
CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- Source file tracking (for change detection)
CREATE TABLE IF NOT EXISTS files (
  path TEXT PRIMARY KEY,
  source TEXT NOT NULL DEFAULT 'memory',
  hash TEXT NOT NULL,           -- SHA-256 of file content
  mtime INTEGER NOT NULL,       -- File modification time (ms)
  size INTEGER NOT NULL          -- File size (bytes)
);

-- Embedded text chunks
CREATE TABLE IF NOT EXISTS chunks (
  id TEXT PRIMARY KEY,           -- UUID
  path TEXT NOT NULL,            -- Source file path
  source TEXT NOT NULL DEFAULT 'memory',  -- 'memory' or 'sessions'
  start_line INTEGER NOT NULL,
  end_line INTEGER NOT NULL,
  hash TEXT NOT NULL,            -- SHA-256 of chunk text
  model TEXT NOT NULL,           -- Embedding model used
  text TEXT NOT NULL,            -- The actual text
  embedding TEXT NOT NULL,       -- JSON array of floats: "[0.1, -0.2, ...]"
  updated_at INTEGER NOT NULL    -- Timestamp (ms)
);
CREATE INDEX IF NOT EXISTS idx_chunks_path ON chunks(path);
CREATE INDEX IF NOT EXISTS idx_chunks_source ON chunks(source);

-- Embedding cache (avoid re-computing)
CREATE TABLE IF NOT EXISTS embedding_cache (
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  provider_key TEXT NOT NULL,
  hash TEXT NOT NULL,            -- SHA-256 of input text
  embedding TEXT NOT NULL,       -- JSON array of floats
  dims INTEGER,                  -- Dimension count
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (provider, model, provider_key, hash)
);
CREATE INDEX IF NOT EXISTS idx_embedding_cache_updated_at ON embedding_cache(updated_at);

-- Full-text search index
CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
  text,                          -- Indexed: full-text searchable
  id UNINDEXED,                  -- Not indexed: stored for retrieval only
  path UNINDEXED,
  source UNINDEXED,
  model UNINDEXED,
  start_line UNINDEXED,
  end_line UNINDEXED
);
```

### Embedding Storage Format

Embeddings are stored as JSON text in SQLite:

```
"[0.023, -0.145, 0.892, 0.034, -0.567, ...]"
```

To use them, parse JSON → Float32Array → compute cosine similarity.

With sqlite-vec extension, embeddings are stored as binary BLOB (Float32Array buffer) in the `chunks_vec` table for efficient vector operations.

## Log Rotation

### Daily Rolling

```
getLogFilePath():
  today = formatDate(new Date())    # "2026-03-08"
  return path.join(logDir, "openclaw-" + today + ".log")
```

New day = new file. No explicit rotation logic — the date in the filename handles it.

### Size Cap

```
State: currentFileBytes (in-memory counter)

appendLog(payload):
  payloadBytes = Buffer.byteLength(payload)
  nextBytes = currentFileBytes + payloadBytes

  if nextBytes > maxFileBytes:      # default: 500 MB
    if not alreadyWarned:
      appendFileSync(file, "Log file size limit reached\n")
      alreadyWarned = true
    return                          # silently drop

  appendFileSync(file, payload)
  currentFileBytes = nextBytes
```

### Old Log Cleanup

```
pruneOldLogs(logDir):
  cutoff = Date.now() - 24 * 60 * 60 * 1000    # 24 hours ago
  pattern = /^openclaw-\d{4}-\d{2}-\d{2}\.log$/

  for file in readdir(logDir):
    if pattern.test(file):
      stat = fs.stat(file)
      if stat.mtimeMs < cutoff:
        fs.rm(file)
```

Only runs once at logger initialization, not continuously.

## Auth Profile Store

### Read/Write Pattern

```
Read:
  raw = fs.readFileSync(authPath, "utf-8")
  store = JSON.parse(raw)
  # Merge OAuth credentials from external files
  # Sync CLI credentials (AWS, etc.)
  return store

Write (with lock):
  lock = await acquireFileLock(authPath + ".lock", {
    retries: 5,
    factor: 2,
    minTimeout: 100,
    maxTimeout: 2000,
    stale: 30000
  })

  try:
    current = readAuthStore(authPath)
    mutated = applyMutation(current)
    sanitized = sanitizeCredentials(mutated)    # remove decrypted secrets
    content = JSON.stringify(sanitized, null, 2)
    writeTextAtomic(authPath, content)
  finally:
    lock.release()
```

The file lock uses the same exponential backoff retry pattern as the session write lock, but with shorter timeouts (appropriate for small config files).
