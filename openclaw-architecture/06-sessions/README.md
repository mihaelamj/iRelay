# 06 — Session Management

Sessions are the backbone of conversation persistence. Every conversation — whether a DM, group chat, subagent task, or cron job — is tracked as a session. Sessions store the message history, model preferences, token usage, delivery context, and more.

## What Is a Session?

A session is a conversation context that ties together:
- **Who** is talking (sender ID, channel, account)
- **Which agent** is handling it
- **What model** is being used
- **The conversation history** (stored as a JSONL transcript file)
- **Runtime state** (thinking level, queue mode, delivery context)

## Session Entry — All Fields

Here is every field a session entry can contain:

### Identity & Lifecycle
- `sessionId`: UUID (format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)
- `updatedAt`: Millisecond timestamp of last modification
- `sessionFile`: Path to the JSONL transcript file
- `compactionCount`: How many times the transcript has been compacted

### Model & Execution
- `model`: Current model identifier (e.g., `"claude-opus-4-6"`)
- `modelProvider`: Current provider (e.g., `"anthropic"`)
- `providerOverride`: User-forced provider override
- `modelOverride`: User-forced model override
- `contextTokens`: Cached token limit for the active model
- `authProfileOverride`: Forced auth profile
- `authProfileOverrideSource`: `"auto"` or `"user"`

### Token Usage
- `inputTokens`: Input tokens from last run
- `outputTokens`: Output tokens from last run
- `totalTokens`: Total context window utilization
- `totalTokensFresh`: Whether totalTokens is fresh from latest run
- `cacheRead`: Tokens from prompt cache hits
- `cacheWrite`: Tokens written to prompt cache

### Message Queue
- `queueMode`: How incoming messages are handled:
  - `"steer"`: New message steers current run
  - `"followup"`: Queue as follow-up after current run
  - `"collect"`: Batch messages together
  - `"queue"`: FIFO queue
  - `"interrupt"`: Abort current run, start new
- `queueDebounceMs`: Delay before processing queued messages
- `queueCap`: Maximum pending messages
- `queueDrop`: What to do when cap is reached (`"old"`, `"new"`, `"summarize"`)

### Behavior
- `thinkingLevel`: `"on"` or `"off"` — extended thinking
- `verboseLevel`: `"on"` or `"off"` — show tool output
- `reasoningLevel`: Detail level for reasoning
- `elevatedLevel`: Elevated privileges mode
- `ttsAuto`: Text-to-speech auto-play mode
- `responseUsage`: Token usage display (`"on"`, `"off"`, `"tokens"`, `"full"`)

### Chat Context
- `chatType`: `"direct"`, `"group"`, `"channel"`, `"unknown"`
- `channel`: Channel provider (e.g., `"telegram"`, `"slack"`)
- `groupId`: Group identifier
- `subject`: Group topic/name
- `groupChannel`: Channel name within group (e.g., `"#general"`)
- `space`: Workspace identifier

### Delivery
- `deliveryContext`: `{ channel, to, accountId, threadId }`
- `lastChannel`: Last delivery channel used
- `lastTo`: Last recipient
- `lastAccountId`: Last account used
- `lastThreadId`: Last thread ID

### Hierarchy
- `spawnedBy`: Parent session key (for subagents)
- `spawnDepth`: Nesting depth (0 = main, 1+ = subagent)
- `forkedFromParent`: Whether transcript was forked from parent

### Group Activation
- `groupActivation`: `"mention"` or `"always"`
- `groupActivationNeedsSystemIntro`: Whether intro message needed

### Labels & Display
- `label`: User-facing session label (max 64 chars)
- `displayName`: Computed display name for group sessions

### Memory Integration
- `memoryFlushAt`: When memory was last flushed
- `memoryFlushCompactionCount`: Compaction count at flush time

## Session Types

### Main Session

The default conversation for each agent:
- Key format: `agent:main:main`
- One per agent (unless scope changes)
- Used for DMs that collapse into a single conversation

### DM Session

Per-user direct message conversation:
- Key format: `agent:main:dm:user123`
- Created when a specific user messages the agent

### Group Session

Per-group conversation:
- Key format: `agent:main:group:slack-team:channel:C123`
- Each group/channel combination gets its own session
- Includes `groupId`, `subject`, `groupChannel`, `space`

### Thread Session

Nested within a main or group session:
- Key format: `agent:main:dm:user123:thread:threadId`
- Markers: `:thread:` for most channels, `:topic:` for Telegram
- Can be forked from parent transcript

### Subagent Session

Isolated session for child agents:
- Key format: `agent:main:subagent:uuid-here`
- Tracks `spawnDepth` for nesting limits
- Auto-cleaned up after completion (unless `cleanup: "keep"`)

### Cron Session

Session for scheduled jobs:
- Key format: `agent:main:cron:job-id`
- Created and destroyed per job execution

## Transcript Storage (JSONL)

Conversation history is stored as **JSONL** (JSON Lines) files — one JSON object per line.

### File Location

```
~/.openclaw/state/agents/{agentId}/sessions/{sessionId}.jsonl
```

For threads:
```
{sessionId}-topic-{topicId}.jsonl
{sessionId}-thread-{threadId}.jsonl
```

### File Format

**First line (header)**:
```json
{"type":"session","version":5,"id":"uuid-here","timestamp":"2026-03-08T12:00:00Z","cwd":"/Users/me"}
```

**Subsequent lines (messages)**:
```json
{"role":"user","content":"Hello","timestamp":"2026-03-08T12:00:01Z"}
{"role":"assistant","content":"Hi there!","model":"claude-opus-4-6","provider":"anthropic","usage":{"input":50,"output":12},"stopReason":"end_turn","timestamp":"2026-03-08T12:00:02Z"}
```

Each line is a complete JSON object. This makes it easy to append (just write a new line) and efficient to read (stream line by line).

## Session Store

The session store is a JSON file that tracks all active sessions:

### Location

```
~/.openclaw/state/sessions.json
```

### Structure

```json
{
  "agent:main:main": {
    "sessionId": "uuid-here",
    "updatedAt": 1709904000000,
    "model": "claude-opus-4-6",
    "totalTokens": 5000,
    "channel": "telegram",
    ...
  },
  "agent:main:dm:user123": { ... },
  "agent:coding:group:slack:channel:C123": { ... }
}
```

### Caching

- In-memory cache with 45-second TTL
- Cache key: `{storePath}:{mtime}:{size}`
- Invalidated when file is modified on disk
- Can be disabled: `OPENCLAW_SESSION_CACHE_TTL_MS=0`

### Locking

Writes to the session store are serialized:
- Per-storePath lock queues prevent concurrent writes
- `withSessionStoreLock()` ensures only one write at a time
- This prevents corruption from simultaneous updates

## Write-Lock Mechanism

Individual transcript files (JSONL) have their own write locks.

### Lock File

```
{sessionFile}.lock
```

Contains:
```json
{"pid": 12345, "createdAt": "2026-03-08T12:00:00Z", "starttime": 1709904000}
```

### Acquisition

1. Try to create lock file with exclusive flag (`wx`)
2. If file exists: Check if existing lock is stale
3. If stale: Remove and retry with exponential backoff
4. Timeout after 10 seconds

### Staleness Detection

A lock is considered stale if any of:
- PID field is missing
- Process with that PID is dead
- PID has been recycled (different process start time)
- Lock creation timestamp is invalid
- Lock is older than 30 minutes

### Watchdog

A global watchdog runs every 60 seconds:
- Checks all held locks
- Force-releases locks held longer than 5 minutes
- Process exit hooks clean up all locks synchronously

### Reentrant Locks

Same process can acquire the same lock multiple times:
- Count-based (each acquire increments, each release decrements)
- Actual cleanup happens when count reaches 0

## Session Freshness & Reset

Sessions can be reset based on freshness:

### Freshness Evaluation

```
SessionResetPolicy:
  type: "daily" | "idle"
  dailyResetHour: number     # Hour of day (0-23)
  idleTimeoutMs: number      # Inactivity timeout
```

- **daily**: Session resets at a specific hour each day
- **idle**: Session resets after inactivity period

### Fresh vs Stale

- `fresh`: Active session within reset window
- `stale`: Session past the reset boundary

When a session becomes stale, it may be compacted or reset depending on configuration.

## Compaction & Pruning

### Compaction

When a transcript gets too long (too many tokens or messages):
1. Create a summary of older turns
2. Prune the oldest messages
3. Merge summaries into context
4. Increment `compactionCount`

Compaction is triggered by:
- Token budget exceeded
- Message count threshold hit
- Manual `/new` or `/reset` command

### Pruning Configuration

```
SessionMaintenanceConfig:
  pruneAfter: "30d"           # Remove sessions older than 30 days
  maxEntries: 500             # Maximum session entries
  rotateBytes: 10MB           # Rotate transcript when it exceeds this
  maxDiskBytes: optional      # Total disk budget for all transcripts
  highWaterBytes: 80%         # Trigger cleanup at this level
```

### Pruning Logic

1. **Age-based**: Remove sessions where `updatedAt < now - pruneAfter`
2. **Count-based**: When entries exceed `maxEntries`, remove oldest
3. **Disk-based**: When total disk exceeds `highWaterBytes`, remove oldest transcripts
4. **Active protection**: The currently active session is never pruned

### Transcript Rotation

When a JSONL file exceeds `rotateBytes` (default 10MB):
1. Create an archive file with date/time suffix
2. Start a new transcript file
3. Archives are retained for `resetArchiveRetention` (default = `pruneAfter`)

## Key Implementation Files

| File | Purpose |
|------|---------|
| `src/config/sessions/` | Session types, store, management |
| `src/sessions/` | Session routing and lifecycle |
| `src/agents/session-write-lock.ts` | Write-lock mechanism |
| `src/context-engine/types.ts` | Context engine interface |

## Swift Replication Notes

1. **Session model**: Codable struct with all fields above
2. **JSONL storage**: Append-only file I/O (one JSON line per write)
3. **Session store**: Actor-based JSON file with in-memory cache
4. **Write locks**: File-based locks with PID tracking (use `flock` on macOS)
5. **Compaction**: Summarize old messages using the LLM itself
6. **Pruning**: Background task that periodically cleans old sessions
