# 17 — Infrastructure

The infrastructure layer provides foundational utilities used throughout OpenClaw: paths, errors, HTTP helpers, retry policies, rate limiting, and logging.

## Path Management

### Standard Paths

```
~/.openclaw/                      # Root state directory
~/.openclaw/openclaw.json         # Main configuration
~/.openclaw/credentials/          # Channel auth tokens
~/.openclaw/state/                # Runtime state
~/.openclaw/state/sessions.json   # Session store
~/.openclaw/state/agents/         # Per-agent state
~/.openclaw/state/agents/{id}/sessions/  # Transcripts
~/.openclaw/state/agents/{id}/memory.db  # Memory database
~/.openclaw/workspace/            # Default workspace
~/.openclaw/skills/               # Managed skills
~/.openclaw/extensions/           # Installed plugins
~/.openclaw/logs/                 # Log files
```

### Path Security

- **Boundary enforcement**: File operations are restricted to workspace boundaries
- **Symlink resolution**: Resolves symlinks and detects loops
- **No traversal**: Prevents `../` escapes from sandbox
- **Hardlink rejection**: Blocks hardlinks that could bypass isolation

## Error Handling

### Error Classification

Errors are categorized to determine retry behavior:

```
Provider Errors:
  auth (401)         → Switch profile, don't retry same
  billing (402)      → Permanent, notify user
  rate_limit (429)   → Backoff, retry
  overloaded (503)   → Short backoff, retry
  timeout (408)      → Short backoff, retry
  format (400)       → Don't retry (bad request)
  model_not_found    → Don't retry
  context_overflow   → Compact and retry
  unknown            → Medium backoff, retry
```

### Retry Policies

**Exponential backoff** is the standard retry pattern:

```
Overload failover:
  initialMs: 250
  maxMs: 1,500
  factor: 2
  jitter: 0.2

Config load retry:
  initialMs: 1,000
  maxMs: 60,000
  factor: 2
```

## HTTP Utilities

### Safe Body Parsing

- Maximum body size: 20 MB
- Content-Type validation
- JSON parsing with error recovery
- Timeout enforcement

### Fetch Guards

- Validates URLs before fetching
- Blocks SSRF attempts (private IPs, localhost)
- Validates origin against allowlists
- Enforces response size limits

## Rate Limiting

### Fixed-Window Rate Limiter

```
Configuration:
  windowMs: 1000       # Window size
  maxRequests: 30       # Max requests per window
  keyGenerator: fn      # How to group requests
```

### Per-Platform Limits

| Platform | Rate Limit |
|----------|-----------|
| Telegram | ~30 msg/sec per bot |
| Discord | 5 requests/5sec per endpoint |
| Slack | 3/sec per workspace |
| WhatsApp | ~60 msg/min per account |
| Signal | ~30 msg/min per account |

### Auth Rate Limiting

- Sliding window per `{scope, clientIp}`
- 10 attempts per 60-second window
- 5-minute lockout after exceeding
- Loopback addresses exempt

## Logging

### Architecture

Built on the `tslog` library:
- Structured JSON log output
- Rolling log files with size caps (default 500 MB)
- Per-subsystem tagged loggers
- Automatic secret redaction

### Log Levels

| Level | Use |
|-------|-----|
| `silly` | Most verbose (everything) |
| `trace` | Detailed tracing |
| `debug` | Debug information |
| `info` | Normal operation (default) |
| `warn` | Warnings |
| `error` | Errors |
| `fatal` | Fatal errors |
| `silent` | No output |

### Subsystem Loggers

Each module creates a tagged logger:

```typescript
const log = createSubsystemLogger("agents/model-selection");
log.info("Model resolved", { provider: "anthropic", model: "claude-opus-4-6" });
```

Output:
```json
{
  "time": "2026-03-08T12:34:56.789Z",
  "level": "info",
  "subsystem": "agents/model-selection",
  "message": "Model resolved",
  "provider": "anthropic",
  "model": "claude-opus-4-6"
}
```

### Secret Redaction

API keys and tokens are automatically masked in log output:
- Pattern-based detection (sk-ant-*, xoxb-*, etc.)
- Bounded redaction window (performance protection)

## Process Management

### Restart Mechanisms

- Graceful restart with PID tracking
- SIGTERM → wait → SIGKILL escalation
- Stale PID detection and cleanup

### Supervisor Integration

- LaunchAgent (macOS) / systemd (Linux)
- Auto-start on boot
- Crash recovery
- Log rotation

## Key Implementation Files

| File | Purpose |
|------|---------|
| `src/infra/` | 298 files total |
| `src/infra/boundary-path.ts` | Path boundary enforcement |
| `src/infra/retry-policy.ts` | Retry configuration |
| `src/infra/retry.ts` | Retry execution |
| `src/infra/http-body.ts` | HTTP body parsing |
| `src/infra/fetch.ts` | Safe HTTP fetching |
| `src/infra/fixed-window-rate-limit.ts` | Rate limiter |
| `src/infra/session-cost-usage.ts` | Token cost tracking |
| `src/logging/logger.ts` | Logger setup |
| `src/logging/redact.ts` | Secret redaction |

## Swift Replication Notes

1. **Paths**: Use `FileManager` with `applicationSupportDirectory`
2. **Errors**: Define Swift enums for error classification
3. **Retries**: Use structured concurrency with `Task.sleep` for backoff
4. **HTTP**: URLSession with timeout and size limit configuration
5. **Rate limiting**: Actor-based sliding window counter
6. **Logging**: Use SwiftClaw's existing `ClawLogging` (wraps swift-log)
7. **Process management**: LaunchAgent plist generation for macOS daemon
