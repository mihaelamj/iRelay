# 10 — Plugin / Extension System

The plugin system is OpenClaw's primary extensibility mechanism. Channels, features, providers, and tools can all be added as plugins without modifying core code. There are 42 extension plugins.

## What Is a Plugin?

A plugin is an **npm package** that registers capabilities with OpenClaw at runtime. Plugins can:
- Add new messaging channels
- Add new LLM providers
- Register tools for the agent
- Hook into lifecycle events (before/after agent, tool calls, messages)
- Register CLI commands
- Add skills

## Plugin Discovery

### Where Plugins Live

Plugins are discovered from three roots:

1. **Bundled**: Shipped inside the OpenClaw package (`extensions/`)
2. **Global**: `~/.openclaw/extensions/` (user-installed)
3. **Workspace**: Per-agent workspace extensions

### Security Checks

During discovery, OpenClaw verifies:
- No path escaping (symlinks that leave the plugin directory)
- No world-writable directories (security risk)
- Ownership matches expected user
- Manifest file exists and is valid JSON

### Discovery Cache

Results are cached with a configurable window (default 1 second) to avoid rescanning on every request.

## Plugin Manifest

Every plugin needs an `openclaw.plugin.json` (or declares in `package.json`):

```json
{
  "id": "my-plugin",
  "name": "My Plugin",
  "description": "Does amazing things",
  "version": "1.0.0",

  "kind": "memory",

  "channels": ["telegram", "slack"],
  "providers": ["anthropic", "openai"],
  "skills": ["relative/path/to/skills"],

  "configSchema": {
    "type": "object",
    "properties": {
      "apiKey": { "type": "string" },
      "enabled": { "type": "boolean" }
    }
  },

  "uiHints": {
    "apiKey": {
      "label": "API Key",
      "help": "Your API key for the service",
      "advanced": false
    }
  }
}
```

## Plugin Lifecycle

### 1. Discovery
Scan all plugin roots for valid manifests.

### 2. Validation
- Check manifest schema
- Validate config schema (if provided)
- Check plugin kind compatibility

### 3. Initialization
Load plugin modules via dynamic import (Jiti for TypeScript).

### 4. Runtime Setup
Plugin registers its capabilities:
- Tools → Agent tool registry
- Hooks → Hook priority queue
- Commands → CLI command tree
- Channels → Channel plugin registry
- Providers → Provider registry

### 5. Active
Plugin hooks fire during normal operation.

## Plugin SDK

The SDK provides types and helpers for plugin developers:

```typescript
import {
  type ChannelPlugin,
  type ChannelGatewayContext,
  registerTool,
  registerCommand,
  registerHook,
  registerProvider,
  registerChannel,
} from "openclaw/plugin-sdk";
```

### SDK Exports (50+ subpaths)

The Plugin SDK has extensive subpath exports:
- `openclaw/plugin-sdk/compat` — Shared helpers
- `openclaw/plugin-sdk/discord` — Discord-specific types
- `openclaw/plugin-sdk/slack` — Slack-specific types
- `openclaw/plugin-sdk/telegram` — Telegram-specific types
- And many more

## Hook System

Hooks let plugins intercept and modify behavior at key points in the lifecycle. Each hook has a **priority** — higher priority hooks execute first.

### Available Hooks

**Agent Lifecycle:**
| Hook | When It Fires | What You Can Do |
|------|---------------|-----------------|
| `beforeAgentStart` | Before agent run begins | Modify system prompt, inject context |
| `beforeModelResolve` | Before model selection | Override model/provider |
| `beforePromptBuild` | Before prompt assembly | Inject custom prompt sections |
| `agentEnd` | After agent run completes | Cleanup, logging |

**Model/LLM:**
| Hook | When It Fires | What You Can Do |
|------|---------------|-----------------|
| `llmInput` | Before LLM API call | Observe/log the input |
| `llmOutput` | After LLM response | Observe/log the output |

**Tool Execution:**
| Hook | When It Fires | What You Can Do |
|------|---------------|-----------------|
| `beforeToolCall` | Before tool executes | Validate, modify, or block |
| `afterToolCall` | After tool completes | Post-process results |
| `toolResultPersist` | Before result is logged | Control what gets stored |

**Message Handling:**
| Hook | When It Fires | What You Can Do |
|------|---------------|-----------------|
| `messageReceived` | Inbound message arrives | Process, filter, enrich |
| `messageSending` | Before outbound delivery | Validate, modify |
| `messageSent` | After successful delivery | Logging, analytics |
| `beforeMessageWrite` | Before writing to transcript | Filter what gets recorded |

**Session Management:**
| Hook | When It Fires | What You Can Do |
|------|---------------|-----------------|
| `sessionStart` | Session begins | Initialize custom state |
| `sessionEnd` | Session ends | Cleanup |
| `beforeReset` | Before session reset | Backup, export |

**Subagent Coordination:**
| Hook | When It Fires | What You Can Do |
|------|---------------|-----------------|
| `subagentSpawning` | Before spawn | Validate, configure |
| `subagentSpawned` | After spawn | Track, setup |
| `subagentDeliveryTarget` | Delivery routing | Override target |
| `subagentEnded` | After completion | Cleanup |

**Compaction:**
| Hook | When It Fires | What You Can Do |
|------|---------------|-----------------|
| `beforeCompaction` | Before memory compaction | Pre-process |
| `afterCompaction` | After compaction | Validate |

**Gateway:**
| Hook | When It Fires | What You Can Do |
|------|---------------|-----------------|
| `gatewayStart` | Gateway boots | Bootstrap |
| `gatewayStop` | Gateway shuts down | Cleanup |

## Plugin Runtime

When a plugin runs, it gets access to the runtime context:

```typescript
PluginRuntime = {
  config: ConfigLoader,           // Read configuration
  workspaceDir: string,           // Agent workspace path
  agentDir: string,               // Agent config directory
  agentId: string,                // Current agent ID

  subagent: {
    run(params)                   // Spawn a subagent turn
    waitForRun(params)            // Wait for subagent completion
    getSessionMessages()          // Read conversation history
    deleteSession()               // Clean up session
  },

  channel: {
    // Channel-specific APIs
  },

  logger: PluginLogger            // Structured logging
}
```

## All 42 Extensions

### Channel Extensions (18)
acpx, bluebubbles, discord, feishu, googlechat, imessage, irc, line, matrix, mattermost, msteams, nextcloud-talk, nostr, signal, slack, synology-chat, telegram, tlon, twitch, whatsapp, zalo, zalouser

### Feature Extensions (24)
copilot-proxy, device-pair, diagnostics-otel, diffs, google-gemini-cli-auth, llm-task, lobster, memory-core, memory-lancedb, minimax-portal-auth, open-prose, phone-control, qwen-portal-auth, shared, talk-voice, test-utils, thread-ownership, voice-call

## CLI Commands

```bash
openclaw plugins list                    # Show installed plugins
openclaw plugins install @openclaw/plugin-discord   # Install from npm
openclaw plugins install file:///path/to/plugin      # Install local
openclaw plugins update discord          # Update specific plugin
openclaw plugins uninstall discord       # Remove plugin
openclaw plugins info discord            # Show details
openclaw plugins enable discord          # Enable
openclaw plugins disable discord         # Disable
```

## Swift Replication Notes

1. **Plugin loading**: Swift Package Manager dynamic libraries or a protocol-based registration system
2. **Hook system**: Use a priority queue pattern with async handlers
3. **Plugin SDK**: Define Swift protocols that plugins conform to
4. **Discovery**: Scan directories for plugin manifests (JSON or Swift Package)
5. **Start simple**: Focus on the hook system first, then add plugin loading
6. **Consider**: Swift macros or property wrappers for hook registration
