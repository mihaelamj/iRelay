# 18 — Storage & Persistence

OpenClaw uses a mix of **JSON files**, **JSONL transcripts**, and **SQLite databases** for persistence. There is no central database server — everything is local files.

## Storage Locations

```
~/.openclaw/
├── openclaw.json                    # Main configuration
├── agent-auth.json                  # Auth profiles (API keys, OAuth tokens)
├── credentials/                     # Channel-specific credentials
│   ├── telegram.json
│   ├── slack.json
│   └── discord.json
├── state/
│   ├── sessions.json                # Session store (all session entries)
│   └── agents/
│       ├── main/
│       │   ├── sessions/
│       │   │   ├── uuid-1.jsonl     # Conversation transcript
│       │   │   ├── uuid-1.jsonl.lock  # Write lock
│       │   │   ├── uuid-2.jsonl
│       │   │   └── uuid-2-topic-123.jsonl  # Thread transcript
│       │   └── memory.db            # Vector embeddings (SQLite)
│       └── coding/
│           ├── sessions/
│           └── memory.db
├── workspace/                       # Default agent workspace
│   ├── MEMORY.md                   # Main memory file
│   └── memory/
│       ├── projects.md
│       └── 2026-03-08.md
├── skills/                          # Managed skills
├── extensions/                      # Installed plugins
└── logs/                            # Log files
```

## Config Storage (JSON)

### openclaw.json

The main configuration file. See [16-config](../16-config/) for full details.

- Format: JSON with comments support
- Atomic writes: Write to temp file, then rename
- Validation: Zod schema on every load
- Migration: Auto-upgrade between versions

### agent-auth.json

Auth profiles for LLM providers:

```json
{
  "version": 1,
  "profiles": [
    {
      "id": "profile-1",
      "provider": "anthropic",
      "mode": "api-key",
      "credential": { "apiKey": "sk-ant-..." },
      "lastUsed": 1709904000000,
      "lastGood": 1709904000000,
      "cooldownUntil": null,
      "usageStats": {
        "errorCount": 0,
        "failureCounts": {}
      }
    }
  ],
  "order": {
    "anthropic": ["profile-1", "profile-2"]
  }
}
```

- Lock-protected writes (prevents concurrent corruption)
- Cooldown tracking per profile
- Usage statistics for selection decisions

## Session Storage (JSON + JSONL)

### sessions.json

A JSON file mapping session keys to session entries:

```json
{
  "agent:main:main": {
    "sessionId": "uuid-here",
    "updatedAt": 1709904000000,
    "model": "claude-opus-4-6",
    "totalTokens": 5000,
    "channel": "telegram"
  }
}
```

- Cached in memory (45-second TTL)
- Serialized writes via per-store lock queue
- Normalized on load (cleanup stale fields)

### JSONL Transcripts

Each conversation is a `.jsonl` file — one JSON object per line:

**Header (first line)**:
```json
{"type":"session","version":5,"id":"uuid","timestamp":"2026-03-08T12:00:00Z","cwd":"/path"}
```

**Messages (subsequent lines)**:
```json
{"role":"user","content":"Hello","timestamp":"2026-03-08T12:00:01Z"}
{"role":"assistant","content":"Hi!","model":"claude-opus-4-6","usage":{"input":50,"output":5}}
```

**Write protection**:
- `.jsonl.lock` files prevent concurrent writes
- PID-based lock with staleness detection
- Watchdog timer force-releases locks held > 5 minutes

**Rotation**:
- Files rotate at 10 MB (configurable)
- Archives retain for `pruneAfter` duration (default 30 days)
- Archives have date/time suffix

## SQLite Storage

### Memory Database

Per-agent SQLite database for vector embeddings:

```
~/.openclaw/state/agents/{agentId}/memory.db
```

Tables:
- `meta`: Key-value metadata (vector dimensions)
- `files`: Source file tracking (path, hash, mtime)
- `chunks`: Embedded text chunks with vectors
- `chunks_vec`: Vector index (sqlite-vec extension)
- `chunks_fts`: Full-text search index (FTS5)
- `embedding_cache`: Cached embeddings to avoid re-computation

See [07-memory](../07-memory/) for full schema details.

## Credential Storage

### Channel Credentials

Per-channel credential files:

```
~/.openclaw/credentials/telegram.json
~/.openclaw/credentials/slack.json
```

These store channel-specific auth tokens, session data, and OAuth tokens.

### Secrets

API keys can be stored in multiple ways (see [16-config](../16-config/)):
- Environment variables (most common)
- Config file (plaintext, not recommended)
- External files (Kubernetes secrets)
- Executable output (dynamic credentials)

## File Safety

### Atomic Writes

All important files use atomic write patterns:
1. Write to temporary file (same directory)
2. `fsync` the temporary file
3. Rename temporary file to target (atomic on POSIX)

This prevents corruption from crashes during write.

### Lock Files

Two types of locks:

1. **Store locks**: In-memory mutexes for session store writes
2. **File locks**: `.lock` files for JSONL transcript access

File locks contain PID and process start time for staleness detection.

### Backup Support

```bash
openclaw backup create    # Create backup archive
openclaw backup verify    # Verify backup integrity
```

Backups include config, credentials, session store, and transcripts.

## Data Lifecycle

### Session Data

| Action | When | What Happens |
|--------|------|-------------|
| Creation | First message | Session entry created in sessions.json |
| Update | Every turn | `updatedAt` timestamp updated |
| Compaction | Context overflow | Old messages summarized, transcript shortened |
| Rotation | File > 10 MB | Archive old file, start fresh |
| Pruning | Maintenance | Remove sessions older than 30 days |
| Disk budget | Overflow | Remove oldest transcripts until under budget |

### Memory Data

| Action | When | What Happens |
|--------|------|-------------|
| Sync | Session start, search, or interval | Scan files, embed new/changed chunks |
| Search | Agent queries memory | Vector + FTS hybrid search |
| Cleanup | File deleted | Remove chunks for deleted files |
| Re-index | Manual or provider change | Re-embed all chunks |

## Swift Replication Notes

1. **Config**: Codable JSON files in `~/.irelay/`
2. **JSONL**: Line-by-line append using FileHandle
3. **SQLite**: GRDB (already in iRelay) for memory and potentially sessions
4. **Atomic writes**: Use `FileManager.replaceItem(at:withItemAt:)` on macOS
5. **File locks**: Use `flock()` system call or custom lock files
6. **Keychain**: Use iRelay's `IRelaySecurity` for credential storage (more secure than JSON files)
7. **Consider**: Using GRDB for sessions too (instead of JSON) for better query support
