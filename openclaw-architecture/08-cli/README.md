# 08 — CLI Commands

The CLI is how you interact with OpenClaw from the terminal. It uses **Commander.js** for command parsing and supports 40+ commands organized into core commands and subcli groups.

## Architecture

### Entry Point

```
openclaw.mjs → entry.ts → run-main.ts → buildProgram() → Commander.parseAsync()
```

1. `entry.ts`: Respawns process to suppress Node.js warnings, fast-paths `--version` and `--help`
2. `run-main.ts`: Normalizes argv, loads environment, validates runtime
3. `buildProgram()`: Creates Commander instance, registers all commands
4. Commands are **lazy-loaded** — only the targeted command's code is loaded

### Lazy Registration

To keep startup fast, commands register a stub first. The actual handler is only loaded when the command is invoked. This matters because OpenClaw has 295+ command files.

## Command Tree

### Core Commands (18 primary)

| Command | What It Does |
|---------|-------------|
| `openclaw setup` | Initialize local config and agent workspace |
| `openclaw onboard` | Interactive wizard for first-time setup |
| `openclaw configure` | Interactive setup for credentials/channels/agents |
| `openclaw config` | Non-interactive config helpers (get/set/unset/validate) |
| `openclaw backup` | Create/verify local backup archives |
| `openclaw doctor` | Health checks and quick fixes |
| `openclaw dashboard` | Open the web Control UI |
| `openclaw reset` | Reset local config/state |
| `openclaw uninstall` | Uninstall gateway service |
| `openclaw message` | Send/read/manage messages |
| `openclaw memory` | Search and reindex memory files |
| `openclaw agent` | Run one agent turn via Gateway |
| `openclaw agents` | Manage isolated agents |
| `openclaw status` | Show channel health and recent sessions |
| `openclaw health` | Fetch health from running gateway |
| `openclaw sessions` | List stored conversation sessions |
| `openclaw browser` | Manage OpenClaw's dedicated browser |
| `openclaw update` | Update CLI and gateway |

### Subcli Groups (25+ groups with subcommands)

| Group | Subcommands | Purpose |
|-------|-------------|---------|
| `gateway` | `start`, `stop`, `status`, `logs` | Run and manage the WebSocket gateway |
| `daemon` | `install`, `uninstall`, `status` | System service management (launchd/systemd) |
| `channels` | `list`, `start`, `stop`, `login`, `logout`, `status` | Manage messaging channels |
| `models` | `list`, `scan`, `info` | Discover and configure LLM models |
| `cron` | `at`, `every`, `list`, `get`, `delete`, `pause`, `resume` | Schedule jobs |
| `plugins` | `list`, `install`, `update`, `uninstall`, `enable`, `disable`, `info` | Extension management |
| `skills` | `list`, `info`, `check` | Skill discovery and validation |
| `nodes` | `list`, `approve`, `revoke` | Manage gateway-owned node pairing |
| `devices` | `list`, `pair`, `unpair`, `approve` | Device pairing and token management |
| `approvals` | `list`, `approve`, `deny`, `config` | Execution approval workflows |
| `sandbox` | `start`, `stop`, `status`, `shell` | Docker sandbox management |
| `secrets` | `list`, `set`, `get`, `delete` | Credential management |
| `hooks` | `list`, `add`, `remove` | Plugin hook management |
| `webhooks` | `list`, `create`, `delete` | Webhook management |
| `logs` | `tail`, `search` | Gateway log access |
| `system` | `events`, `heartbeat`, `presence` | System-level operations |
| `directory` | `users`, `channels`, `threads` | List users/channels/threads |
| `dns` | `set`, `get` | DNS upstream configuration |
| `docs` | (opens browser) | Open documentation |
| `tui` | (launches TUI) | Terminal UI connected to Gateway |
| `acp` | Various | Agent Control Protocol tools |
| `node` | `run`, `status` | Headless node host service |
| `completion` | `bash`, `zsh`, `fish` | Shell completion scripts |
| `qr` / `pairing` | Various | Device pairing via QR code |
| `browser` | `start`, `stop`, `list`, `inspect`, `resize`, `manage`, `state` | Browser session control |

### Plugin Commands

Plugins can register additional commands dynamically. These are loaded after core/subcli registration.

## Key Command Details

### `openclaw onboard`

The interactive setup wizard. Options:

```bash
openclaw onboard \
  --flow quickstart|advanced|manual \
  --mode local|remote \
  --auth-choice anthropic|openai|custom|token|skip \
  --workspace /path/to/dir \
  --gateway-port 18789 \
  --gateway-bind loopback|tailnet|lan|auto|custom \
  --tailscale off|serve|funnel \
  --install-daemon \
  --node-manager npm|pnpm|bun \
  --non-interactive --accept-risk
```

Walks through: risk acknowledgment → gateway config → auth/model setup → workspace → channels → skills → health check.

### `openclaw agent`

Run a single agent turn:

```bash
openclaw agent "What is the weather in Tokyo?" \
  --agent main \
  --model anthropic/claude-opus-4-6 \
  --thinking on \
  --verbose full
```

### `openclaw cron`

Schedule jobs:

```bash
openclaw cron at "2026-03-10T14:30:00Z" "remind me about the meeting"
openclaw cron every 30m "check server status" --deliver
openclaw cron every "0 9 * * *" "good morning" --delivery-target telegram:123456
openclaw cron list --json
```

### `openclaw channels`

```bash
openclaw channels list
openclaw channels start discord:work
openclaw channels stop telegram:default
openclaw channels login whatsapp --force
openclaw channels logout slack:personal
openclaw channels status
```

## Key Implementation Files

| File | Purpose |
|------|---------|
| `src/entry.ts` | Process entry point |
| `src/cli/run-main.ts` | CLI bootstrap |
| `src/cli/program/build-program.ts` | Commander setup |
| `src/cli/program/command-registry.ts` | Core command registration |
| `src/cli/program/register.subclis.ts` | Subcli group registration |
| `src/commands/` | 295 command implementation files |

## Swift Replication Notes

1. **CLI framework**: Swift Argument Parser (already in SwiftClaw)
2. **Command structure**: Use `ParsableCommand` with subcommands
3. **Lazy loading**: Not needed in Swift (compiled, no module loading cost)
4. **Interactive wizard**: Use Swift's `readLine()` or a TUI library
5. **Start with**: `serve`, `chat`, `config`, `status`, `daemon` (already stubbed)
6. **Expand to**: `channels`, `cron`, `memory`, `models`, `plugins`
