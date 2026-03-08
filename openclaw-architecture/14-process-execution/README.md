# 14 — Process Execution

The process system lets the agent run shell commands on the host machine. This is one of the most powerful (and dangerous) capabilities, so it comes with extensive safety controls.

## Execution Modes

### Direct Exec
Simple command execution with output capture:
- Runs command via shell
- Captures stdout and stderr
- Returns exit code
- Supports timeout

### PTY (Pseudo-Terminal)
Full terminal emulation for interactive commands:
- Allocates a PTY
- Supports interactive input
- Handles ANSI escape codes
- Used for commands that need a terminal (like `vim`, `less`, or interactive installers)

## Approval Workflows

Dangerous commands can require explicit approval before execution:

### Flow
1. Agent wants to run `rm -rf /important/data`
2. OpenClaw detects this as potentially dangerous
3. An `exec.approval.requested` event is sent to connected clients
4. User sees the approval request in their app/CLI
5. User approves or denies
6. If approved: command executes
7. If denied: agent is told the command was blocked

### Configuration

Approval rules can be configured per command pattern. Some commands are always blocked, some always allowed, and some require approval.

## Sandbox Execution

When running in a Docker sandbox:

```
SandboxContext:
  enabled: boolean
  containerWorkspaceDir: "/workspace"
  hostWorkspaceDir: "/Users/me/workspace"
  workspaceAccess: "none" | "ro" | "rw"
```

- **read/write/edit**: Operate on host workspace via bridge
- **exec**: Runs inside the Docker container
- **`/elevated`**: Escapes to host (if allowed)

### Elevated Mode
When sandbox is enabled, the agent can request elevated access:
- Default level: `"off"`, `"on"`, `"ask"`, or `"full"`
- Elevated commands bypass sandbox restrictions
- Requires explicit user approval (unless `"full"` mode)

## Process Supervision

### Child Process Management
- Process tree tracking (parent + all children)
- Kill tree for proper cleanup (kills all descendants)
- PID tracking and stale PID detection

### Command Queue
- Commands are serialized (one at a time by default)
- Prevents concurrent modification issues
- Configurable concurrency limit

### Restart Recovery
- Long-running processes can be restarted on failure
- Configurable restart policies
- Graceful shutdown with SIGTERM → SIGKILL escalation

## CLI Commands

```bash
openclaw approvals list           # Show pending approvals
openclaw approvals approve <id>   # Approve a request
openclaw approvals deny <id>      # Deny a request
openclaw approvals config         # View/edit rules
```

## Key Implementation Files

| File | Purpose |
|------|---------|
| `src/process/exec.ts` | Command execution |
| `src/process/supervisor/` | Process supervision |
| `src/process/child-process-bridge.ts` | IPC bridge |
| `src/cli/exec-approvals-cli.ts` | Approval CLI |

## Swift Replication Notes

1. **Process**: Use Foundation's `Process` class for command execution
2. **PTY**: Use `posix_openpt()` / `forkpty()` for pseudo-terminal support
3. **Approval**: Send events through the Gateway, wait for user response
4. **Sandbox**: Consider using macOS sandbox profiles (`sandbox-exec`) or Docker
5. **Security**: Always validate command paths, prevent shell injection
