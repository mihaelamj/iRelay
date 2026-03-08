# 12 — Cron & Scheduling

The cron system lets you schedule tasks that run automatically — one-time reminders, recurring checks, or periodic agent runs.

## Job Types

### One-Shot (`at`)

Runs once at a specific time:

```bash
openclaw cron at "2026-03-10T14:30:00Z" "remind me about the meeting"
```

### Recurring (`every`)

Runs on a schedule:

```bash
# Interval-based
openclaw cron every 30m "check server status"
openclaw cron every 1h "summarize inbox"
openclaw cron every 1d "daily standup"

# Cron expression
openclaw cron every "0 9 * * *" "good morning"       # 9 AM daily
openclaw cron every "*/15 * * * *" "health check"     # Every 15 minutes
openclaw cron every "0 0 * * 1" "weekly report"       # Monday midnight
```

## Delivery Modes

### Agent Mode (default)

The cron job spawns an isolated agent turn. The agent processes the message, potentially using tools, and the result goes to the session.

### Delivery Mode

The message is sent directly to a channel without agent processing:

```bash
openclaw cron every 1h "Server is healthy" --deliver
openclaw cron every 1h "Good morning!" --delivery-target telegram:123456
```

## Delivery Configuration

```bash
--deliver                              # Send directly to last channel
--delivery-target <channel:id>         # Specify target
--delivery-target telegram:123456      # Telegram user
--delivery-target slack:C123456        # Slack channel
--delivery-target discord:123456789    # Discord channel
```

## Isolated Agent Runs

When a cron job runs as an agent:
1. Creates an isolated session: `agent:main:cron:job-id`
2. Spawns a subagent turn with the cron message
3. Agent processes the message (can use tools, call APIs, etc.)
4. Result is delivered to the configured target
5. Session is cleaned up after completion

## Heartbeat System

OpenClaw supports periodic heartbeat messages:

- Configurable per agent
- Suppresses duplicate heartbeats
- Tracks OK/failure status
- Summary window for grouping

### Heartbeat Configuration

```json
{
  "agents": {
    "defaults": {
      "heartbeat": {
        "enabled": true,
        "intervalMs": 3600000,
        "prompt": "Check system status and report"
      }
    }
  }
}
```

## CLI Commands

```bash
openclaw cron at <datetime> "message"     # One-shot
openclaw cron every <interval|cron> "message" [options]  # Recurring
openclaw cron list [--json]               # List all jobs
openclaw cron get <id>                    # Show job details
openclaw cron delete <id>                 # Remove job
openclaw cron pause <id>                  # Pause job
openclaw cron resume <id>                 # Resume job
```

## Key Implementation Files

| File | Purpose |
|------|---------|
| `src/cron/` | Main cron module |
| `src/cron/schedule.ts` | Schedule parsing (intervals, cron expressions) |
| `src/cron/delivery.ts` | Message delivery logic |
| `src/cron/isolated-agent.ts` | Subagent spawning for cron |
| `src/cron/heartbeat-policy.ts` | Heartbeat deduplication |

## Swift Replication Notes

1. **Scheduler**: Use `DispatchSource.makeTimerSource` or a custom scheduling actor
2. **Cron parsing**: Port or use a Swift cron expression parser
3. **Isolated runs**: Spawn agent turns with dedicated sessions
4. **Persistence**: Store job definitions in GRDB
5. **Start with**: Simple interval-based scheduling, then add cron expressions
