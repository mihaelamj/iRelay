# 03 — Agent Runtime

The Agent system is the **brain** of OpenClaw. It takes incoming messages, builds context, calls an LLM, processes the response (including tool calls), and delivers the reply back to the user. This is the most complex subsystem.

## What Is an Agent?

An agent is a configured AI personality with:
- A unique ID (e.g., `"main"`, `"coding"`, `"writing"`)
- A model preference (e.g., `"anthropic/claude-opus-4-6"`)
- A workspace directory (where it can read/write files)
- A set of allowed tools and skills
- Optional custom behavior (heartbeat, group chat rules, subagent permissions)

One OpenClaw instance can run **multiple agents**. Each agent handles different conversations or different types of tasks. The default agent is always `"main"`.

## Agent Configuration

Here is every field an agent can have:

```
AgentConfig:
  id: string                    # Required. Normalized to [a-z0-9_-]{1,64}
  default: boolean              # Mark as the default agent
  name: string                  # Display name
  workspace: string             # Working directory (supports ~ expansion)
  agentDir: string              # Agent-specific config directory

  model:
    primary: string             # Primary model (e.g., "anthropic/claude-opus-4-6")
    fallbacks: string[]         # Fallback chain if primary fails

  skills: string[]              # ["*"] = all, [] = none, ["skill-id"] = specific

  memorySearch:
    enabled: boolean
    maxResults: number
    windowTokens: number

  humanDelay:                   # Delay between block replies (feels more natural)
    minMs: number
    maxMs: number

  heartbeat:                    # Periodic unprompted messages
    enabled: boolean
    intervalMs: number
    prompt: string

  identity:                     # Avatar/appearance
    avatarPath: string
    displayName: string

  groupChat:                    # How the agent behaves in group chats
    enabled: boolean
    replyPolicy: "proactive" | "reactive"

  subagents:                    # Child agent spawning rules
    allowAgents: string[]       # ["*"] = any, or specific agent IDs
    model: AgentModelConfig     # Default model for spawned children

  sandbox:                      # Docker execution isolation
    enabled: boolean
    image: string
    mounts: [{ host, container }]

  params: Record<string, any>   # Stream params (cache retention, temperature)

  runtime:                      # Execution environment
    type: "embedded" | "acp"    # embedded = in-process, acp = external
    acp:
      agent: string             # ACP adapter name
      backend: string           # ACP backend
      mode: "persistent" | "oneshot"
      cwd: string

  tools:                        # Tool access control
    allow: string[]             # Explicit allowlist
    deny: string[]              # Explicit denylist
    alsoAllow: string[]         # Additive to profile policy
```

## Agent Resolution

When a message arrives, OpenClaw must figure out which agent handles it:

1. **Explicit agent ID** from the request
2. **Session key parsing**: Extract agent ID from `agent:<id>:<rest>` format
3. **Route matching**: Check peer/channel/guild bindings (see Routing below)
4. **Default agent**: Falls back to the agent marked `default: true`
5. **Hard fallback**: If nothing matches, uses agent ID `"main"`

## System Prompt Construction

Before calling the LLM, OpenClaw builds a system prompt dynamically. This prompt tells the AI who it is, what tools it has, and how to behave.

### Prompt Sections (in order)

Each section is conditionally included based on the agent's configuration:

| Section | Always? | Content |
|---------|---------|---------|
| **Identity** | Yes | Agent name, personality |
| **Tooling** | Yes | List of available tools with descriptions |
| **Skills** | If skills enabled | Skill selection guidance |
| **Memory Recall** | If memory enabled | How to search/retrieve memories |
| **CLI Reference** | Yes | OpenClaw command reference |
| **Workspace** | Yes | Working directory and file operation guidance |
| **Documentation** | If docs exist | Links to local/cloud docs |
| **User Identity** | If configured | Authorized sender info |
| **Date/Time** | If timezone set | Current date/time in user's timezone |
| **Model Aliases** | If configured | Short names for providers/models |
| **Sandbox** | If sandboxed | Container paths and constraints |
| **Reactions** | If enabled | Emoji reaction guidelines |
| **Reply Tags** | If not minimal | `[[reply_to_current]]` syntax |
| **Messaging** | If message tool | Channel send and button syntax |
| **Voice (TTS)** | If TTS enabled | Text-to-speech guidance |
| **Group Context** | If in group | Custom group-specific context |
| **Safety** | Always | Safety constraints and boundaries |

### Prompt Modes

- **`full`**: Main agent session — all sections included
- **`minimal`**: Subagent sessions — reduced tooling and context
- **`none`**: Bare minimum — just identity

### Context Files

Agents can have context files that get injected into the prompt:
1. `SOUL.md` — Embedded persona definition
2. Project context files — From the workspace
3. Bootstrap truncation warnings — Added once per session if context is getting large

## Tool Execution

Tools are the agent's hands — they let the AI do things beyond just generating text.

### Built-in Tools

| Tool | What It Does |
|------|-------------|
| `read` | Read file contents |
| `write` | Write/create files |
| `edit` | Edit existing files |
| `apply_patch` | Apply diff patches |
| `grep` | Search file contents |
| `find` | Find files by pattern |
| `ls` | List directory contents |
| `exec` | Run shell commands |
| `process` | Long-running processes |
| `web_search` | Search the web |
| `web_fetch` | Fetch web pages |
| `browser` | Control Chrome via CDP |
| `canvas` | Visual workspace |
| `nodes` | Camera, screen, location |
| `cron` | Schedule jobs |
| `message` | Send messages to channels |
| `gateway` | Gateway control |
| `agents_list` | List configured agents |
| `sessions_list` | List sessions |
| `sessions_history` | Get session history |
| `sessions_send` | Send to session |
| `subagents` | Spawn child agents |
| `session_status` | Get session status |
| `image` | Generate images |

### Tool Policy Pipeline

Before a tool is made available to the agent, it passes through a **policy pipeline** that filters based on context:

1. **Owner-only filtering**: Some tools (gateway, cron, whatsapp_login) only work for the owner
2. **Message provider denials**: Some tools blocked for certain message types (e.g., TTS not allowed via voice channel)
3. **Provider denials**: Some LLM providers can't use certain tools (e.g., X.AI blocks web_search)
4. **Sandbox filtering**: Some tools blocked inside Docker containers
5. **Subagent depth filtering**: Deeper subagents get fewer tools
6. **Group chat filtering**: Per-group tool allowlist/denylist
7. **Core tool policy**: The agent's own `tools.allow`/`tools.deny` config

### Tool Execution Flow

1. The LLM decides to call a tool and includes it in its response
2. OpenClaw checks the **before-tool-call hook** — hooks can block or modify the call
3. The tool's `execute()` function runs with the parameters
4. The result is normalized to `{ content: [{type: "text", text: "..."}], details: {...} }`
5. The result is sent back to the LLM for the next turn
6. The **after-tool-call hook** runs for logging/post-processing

### Before-Tool-Call Hook

A powerful extension point. Hooks can:
- **Block** a tool call: Return `{ blocked: true, reason: "..." }`
- **Modify** parameters: Return adjusted params
- **Allow**: Return nothing (let it proceed)

This is how plugins add approval workflows for dangerous operations.

## Streaming

Agent responses are streamed in real-time, not returned all at once.

### Stream Types

| Stream | What It Contains |
|--------|-----------------|
| `tokens` | Raw text tokens as they're generated |
| `output` | Formatted output blocks |
| `thinking` | Reasoning/thinking content (if enabled) |

### Block Reply Streaming

As the LLM generates text, OpenClaw processes it into "blocks" — complete chunks of content suitable for delivery:

1. **Strip `<think>` blocks**: Internal reasoning is hidden from users
2. **Strip `<final>` tags**: Only content inside `<final>` is shown (if enforce mode)
3. **Remove tool call text**: `[Tool Call: ...]` markers stripped
4. **Deduplicate**: Check against messaging tool sent texts to avoid repeats
5. **Emit block reply**: Send formatted text + media to the channel

### Reasoning Modes

- `"off"`: No reasoning (default) — fastest
- `"on"`: Reasoning happens but is hidden from the user
- `"stream"`: Reasoning is shown in real-time via WebSocket events

### Verbose Modes

- `"off"`: No tool output shown
- `"on"`: Tool summaries only (tool name + brief result)
- `"full"`: Full tool output text included

## Multi-Agent Routing

When a message arrives from a channel, OpenClaw must decide which agent handles it.

### Session Key Format

```
agent:<agentId>:<sessionKey>
```

Examples:
- `agent:main:main` — Default session for the main agent
- `agent:main:dm:user123` — DM with user123 on main agent
- `agent:coding:group:slack-dev:channel:C123` — Coding agent in Slack #dev
- `agent:main:subagent:uuid-here` — A spawned child session
- `agent:main:cron:job-id` — A scheduled job session

### Route Binding Resolution

Routes are matched in priority order:

1. **Peer binding** — Exact peer + channel match (highest priority)
2. **Parent peer binding** — Thread parent matching
3. **Guild + roles binding** — Discord role-based routing
4. **Guild binding** — Server/team match
5. **Team binding** — Microsoft Teams workspace
6. **Account binding** — Slack workspace
7. **Channel binding** — Generic channel match
8. **Default agent** — Fallback (lowest priority)

## Subagent Spawning

Agents can create child agents to handle subtasks.

### Spawn Parameters

```
task: string           # What the child should do
label: string          # Display name
agentId: string        # Target agent (default = parent's agent)
model: string          # Override model
thinking: string       # Override thinking level
runTimeoutSeconds: int # Timeout
thread: boolean        # Bind to thread
mode: "run" | "session"  # Ephemeral or persistent
cleanup: "delete" | "keep"  # Post-completion behavior
sandbox: "inherit" | "require"
attachments: [{ name, content, encoding, mimeType }]
```

### Spawn Flow

1. **Validate**: Check agent ID, spawn depth (max 4), active children (max 5), permissions
2. **Create session**: Generate child session key `agent:<id>:subagent:<uuid>`
3. **Handle attachments**: Decode, write to workspace, add to system prompt
4. **Build system prompt**: Reduced version for subagents
5. **Spawn**: Call gateway `agent` method
6. **Register**: Track for completion announcement
7. **Lifecycle hooks**: Run `subagent_spawned` and `subagent_ended` hooks

### Auto-Announcement

When a subagent finishes, its result is automatically pushed to the parent session as a user message. The parent doesn't need to poll — it just receives the result.

## Auth Profile Management

Each agent call needs API credentials. The auth profile system manages multiple keys per provider.

### Profile Structure

```
AuthProfileCredential:
  id: string                    # Unique profile ID
  provider: string              # e.g., "anthropic", "openai"
  mode: "api-key" | "oauth" | "token"
  credential:
    apiKey: string              # For api-key mode
    oauthToken: string          # For oauth mode
    refreshToken: string        # For oauth refresh
    expiresAt: number           # Token expiry
  lastUsed: number              # When last used
  lastGood: number              # When last succeeded
  failureReason: string         # Why it's failing
  cooldownUntil: number         # When cooldown expires
  usageStats:
    errorCount: number
    failureCounts: { reason: count }
    lastFailureAt: number
```

### Cooldown Timers

When a profile fails, it gets a cooldown based on the failure type:

| Failure | Cooldown | Permanent? |
|---------|----------|-----------|
| Rate limit (429) | 60 seconds | No |
| Overloaded (503) | 10 seconds | No |
| Timeout (408) | 5 seconds | No |
| Auth failure (401) | Until fixed | Yes |
| Billing (402) | Until fixed | Yes |
| Quota exceeded | Until fixed | Yes |
| Other | 5 minutes | No |

### Profile Selection Order

When multiple profiles exist for a provider:
1. Explicit match from session config
2. Ordered config from `auth.order` array
3. Most recently used
4. Last known good
5. First available (sequential)

Profiles in cooldown are skipped.

## Error Handling & Retries

### Retry Budget

```
Base retry iterations: 24
Extra per profile: 8 per auth profile
Formula: 24 + (profileCount * 8)
Minimum: 32 iterations
Maximum: 160 iterations
```

### Retry Strategy by Error Type

| Error | Strategy |
|-------|---------|
| Rate limit | Exponential backoff, try same profile after cooldown |
| Overloaded | Backoff (250ms → 1.5s, 2x factor, 20% jitter) |
| Auth failure | Mark profile, try next profile |
| Billing | Mark profile permanently, try next |
| Context overflow | Attempt compaction, retry with shorter context |
| Timeout | Try same profile after 5s cooldown |

### Error Classification

OpenClaw classifies every error to determine the retry strategy:
- `isAuthAssistantError()` — Checks status code and message
- `isBillingAssistantError()` — 402 or payment-related message
- `isRateLimitAssistantError()` — 429 or rate limit message
- `isCompactionFailureError()` — Compaction-specific
- `isLikelyContextOverflowError()` — Message too long
- `isTimeoutErrorMessage()` — Timeout or abort

## Key Implementation Files

| File | Purpose |
|------|---------|
| `agent-scope.ts` | Agent resolution and workspace setup |
| `system-prompt.ts` | Dynamic system prompt construction |
| `pi-tools.ts` | Tool creation and registration |
| `pi-tool-definition-adapter.ts` | Tool definition adapter |
| `pi-tools.before-tool-call.ts` | Before-tool-call hook |
| `tool-policy-pipeline.ts` | Tool filtering pipeline |
| `pi-embedded-subscribe.ts` | Streaming state machine |
| `pi-embedded-subscribe.handlers.ts` | Event handler routing |
| `pi-embedded-runner/run.ts` | Main agent run loop with retries |
| `subagent-spawn.ts` | Subagent spawning logic |
| `model-auth.ts` | Model auth mode resolution |
| `auth-profiles/types.ts` | Auth profile type definitions |
| `auth-profiles/order.ts` | Profile selection order |
| `auth-profiles/usage.ts` | Cooldown and usage tracking |
| `failover-error.ts` | Error classification |
| `lanes.ts` | Concurrency lanes |
| `pi-embedded-block-chunker.ts` | Block chunking strategy |
| `models-config.providers.ts` | Master provider registry (1,111 lines) |

## Swift Replication Notes

1. **Agent config**: Use Codable structs matching the full config schema
2. **System prompt builder**: A function that conditionally assembles prompt sections
3. **Tool system**: Protocol-based tools with an async `execute` method
4. **Streaming**: Use AsyncStream for token-by-token delivery
5. **Auth profiles**: Actor-based manager with cooldown tracking
6. **Retries**: Structured concurrency with Task cancellation for timeouts
7. **Subagents**: Recursive agent spawning with depth tracking
