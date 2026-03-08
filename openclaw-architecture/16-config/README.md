# 16 — Configuration System

Everything in OpenClaw is configured through a single JSON file: `~/.openclaw/openclaw.json`. The config system handles loading, validation, migration, and hot-reloading.

## Config File Location

```
~/.openclaw/openclaw.json
```

## Top-Level Structure

```json
{
  "version": "2026.3.8",

  "models": {
    "providers": { ... },
    "bedrockDiscovery": { ... }
  },

  "agents": {
    "defaults": { ... },
    "list": [
      { "id": "main", "default": true, ... },
      { "id": "coding", ... }
    ]
  },

  "channels": {
    "telegram": { ... },
    "slack": { ... },
    "discord": { ... }
  },

  "gateway": {
    "bind": "127.0.0.1",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": { "env": "OPENCLAW_GATEWAY_TOKEN" }
    },
    "tls": { ... },
    "tailscale": { ... }
  },

  "security": {
    "dm": { "policy": "allowlist" },
    "group": { "policy": "allowlist" }
  },

  "skills": {
    "entries": { ... },
    "load": { ... }
  },

  "messages": {
    "tts": { ... },
    "humanDelay": { ... }
  },

  "memory": {
    "provider": "auto",
    "query": { ... },
    "sync": { ... }
  },

  "logging": {
    "level": "info",
    "file": true
  }
}
```

## Validation

OpenClaw uses **Zod schemas** for config validation:

- Every section has its own Zod schema
- Schemas are composed into a full config schema
- Validation runs on load, on save, and after migration
- Invalid configs produce helpful error messages

### Per-Section Schemas

| Section | Schema File | What It Validates |
|---------|-------------|-------------------|
| Models | `zod-schema.models.ts` | Provider URLs, API keys, model definitions |
| Agents | `zod-schema.agents.ts` | Agent IDs, model refs, tool policies |
| Channels | `zod-schema.channels.ts` | Channel tokens, group configs, DM policies |
| Gateway | `zod-schema.gateway.ts` | Bind address, port, auth mode, TLS |
| Security | `zod-schema.security.ts` | DM/group policies, allowlists |
| Skills | `zod-schema.skills.ts` | Skill entries, load config |
| Memory | `zod-schema.memory.ts` | Provider, query config, sync settings |

## Secret Inputs

API keys and tokens can come from multiple sources:

```json
// Plaintext (works but not recommended)
"apiKey": "sk-ant-api03-..."

// Environment variable (recommended)
"apiKey": { "env": "ANTHROPIC_API_KEY" }

// File (for Kubernetes/Docker secrets)
"apiKey": { "file": "/run/secrets/anthropic.key" }

// Executable (for dynamic credentials)
"apiKey": { "exec": "aws sso login --profile my-profile" }
```

Secret references are resolved **lazily** — only when the value is actually needed.

## Config Migration

When the config format changes between versions, OpenClaw automatically migrates:

### Migration System

```
1. Load raw JSON from disk
2. Detect version (or lack thereof)
3. Run migration parts in sequence:
   - Part 1: Basic structure changes
   - Part 2: Provider/channel reorgs
   - Part 3: Security/DM policy updates
4. Validate migrated config against current schema
5. Save migrated config
6. Report changes to user
```

### Migration Examples

- Slack token format updates
- Channel configuration restructuring
- DM policy introduction
- New provider additions
- Model definition schema changes

### Safety

- Non-destructive: Original config backed up before migration
- Atomic writes: Write to temp file, then rename
- Validation after migration: Rejects if result is invalid
- Change reporting: Lists all changes made

## Hot-Reloading

Config can be reloaded without restarting:

- Gateway watches config file for changes
- On change: Re-validates, applies delta
- Channels can be started/stopped based on config changes
- Agent config updates take effect on next turn

## Environment Variables

Key environment variables that override config:

| Variable | Overrides |
|----------|-----------|
| `OPENCLAW_GATEWAY_PORT` | `gateway.port` |
| `OPENCLAW_GATEWAY_TOKEN` | `gateway.auth.token` |
| `ANTHROPIC_API_KEY` | Anthropic provider API key |
| `OPENAI_API_KEY` | OpenAI provider API key |
| `GOOGLE_API_KEY` | Google provider API key |

## Key Implementation Files

| File | Purpose | Size |
|------|---------|------|
| `src/config/` | 207 files total | — |
| `src/config/types.openclaw.ts` | Top-level config type | — |
| `src/config/types.models.ts` | Models/provider types | — |
| `src/config/types.agents.ts` | Agent config types | — |
| `src/config/types.channels.ts` | Channel config types | — |
| `src/config/validation.ts` | Zod validation | 500+ lines |
| `src/config/legacy-migrate.ts` | Migration system | — |
| `src/config/legacy.migrations.ts` | Migration rules | — |

## Swift Replication Notes

1. **Config format**: Use Codable structs matching the JSON schema
2. **Validation**: Use Swift's type system + custom validation functions
3. **Secret resolution**: Support env vars (`ProcessInfo.processInfo.environment`) and file reads
4. **Migration**: Version-stamped config with migration functions
5. **Hot-reload**: Use `DispatchSource.makeFileSystemObjectSource` for file watching
6. **Location**: `~/.swiftclaw/config.json` (or similar)
