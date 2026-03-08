# 09 — Skills Platform

Skills are **self-contained capabilities** that extend what the agent can do. Each skill is a markdown file (`SKILL.md`) that describes a tool or integration. When the agent needs to use a skill, the skill's instructions are injected into the system prompt.

## What Is a Skill?

A skill is like a plugin for the agent's brain. Examples:
- **apple-notes**: Read/write Apple Notes
- **github**: Create issues, manage PRs
- **obsidian**: Access Obsidian vault
- **openai-image-gen**: Generate images
- **canvas**: Visual workspace
- **coding-agent**: Spawn a coding subagent

Skills are simpler than plugins — they don't require code. They're just markdown files with metadata that tell the AI how to use a tool.

## Skill Loading Priority

Skills are loaded from multiple locations, highest priority first:

1. **Agent workspace**: `<workspace>/skills/` — agent-specific overrides
2. **Shared managed**: `~/.openclaw/skills/` — installed via ClawHub
3. **Bundled**: Shipped with OpenClaw package
4. **Extra directories**: Configured in `openclaw.json` under `skills.load.extraDirs`

If the same skill exists in multiple locations, the highest-priority version wins.

## SKILL.md Format

Every skill is a markdown file with YAML frontmatter:

```markdown
---
name: weather
description: Get current weather and forecasts for any location
user-invocable: true
disable-model-invocation: false
command-dispatch: tool
command-tool: web_fetch
command-arg-mode: raw
metadata: {"openclaw":{"emoji":"🌤️","homepage":"https://example.com","os":["darwin","linux"],"requires":{"bins":["curl"],"env":["WEATHER_API_KEY"]},"primaryEnv":"WEATHER_API_KEY"}}
---

# Weather Skill

When the user asks about weather, use the web_fetch tool to call the weather API.

## API Endpoint

`GET https://api.weather.com/v1/current?location={location}&key={api_key}`

## Usage

1. Extract the location from the user's message
2. Call the API with the location
3. Format the response nicely

## Examples

User: "What's the weather in Tokyo?"
→ Fetch https://api.weather.com/v1/current?location=Tokyo&key=$WEATHER_API_KEY
→ Format and present the result
```

### Frontmatter Fields

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `name` | string | Required | Unique skill identifier |
| `description` | string | Required | Human-readable description |
| `user-invocable` | boolean | `true` | Can users trigger this skill directly? |
| `disable-model-invocation` | boolean | `false` | Prevent the AI from using this autonomously? |
| `command-dispatch` | string | — | How to dispatch: `"tool"` (call a tool) |
| `command-tool` | string | — | Which tool to call (for `dispatch: tool`) |
| `command-arg-mode` | string | `"raw"` | How to pass arguments |
| `metadata` | JSON | — | OpenClaw-specific metadata (see below) |

### Metadata Object

The `metadata.openclaw` object controls gating and presentation:

```json
{
  "openclaw": {
    "always": false,           // Skip all gates, always load
    "emoji": "🌤️",            // Display emoji
    "homepage": "https://...", // Documentation URL

    "os": ["darwin", "linux"], // Platform filter

    "requires": {
      "bins": ["curl"],        // Required CLI binaries (all must exist)
      "anyBins": ["ffmpeg", "avconv"],  // At least one must exist
      "env": ["API_KEY"],      // Required env vars or config keys
      "config": ["browser.enabled"]  // Required config paths
    },

    "primaryEnv": "WEATHER_API_KEY",  // Main env var for apiKey config

    "install": [               // Installer specs
      {
        "id": "brew",
        "kind": "brew",
        "formula": "curl"
      }
    ]
  }
}
```

## Skill Gating

Before a skill is made available, OpenClaw checks several gates:

1. **Platform gate** (`os`): Is the current OS in the allowed list?
2. **Binary gate** (`requires.bins`): Are all required CLI tools on PATH?
3. **Any-binary gate** (`requires.anyBins`): Is at least one tool on PATH?
4. **Environment gate** (`requires.env`): Are all required env vars set?
5. **Config gate** (`requires.config`): Are all required config paths truthy?
6. **Always gate**: If `always: true`, skip all other gates

If any gate fails, the skill is not loaded. This prevents the agent from trying to use tools that aren't available.

## Skill Configuration

Skills can be configured in `openclaw.json`:

```json
{
  "skills": {
    "entries": {
      "weather": {
        "enabled": true,
        "apiKey": {
          "source": "env",
          "provider": "default",
          "id": "WEATHER_API_KEY"
        },
        "env": {
          "WEATHER_API_KEY": "your-key-here"
        },
        "config": {
          "custom_field": "custom_value"
        }
      }
    },
    "load": {
      "watch": true,
      "watchDebounceMs": 250,
      "extraDirs": ["/path/to/custom/skills"]
    }
  }
}
```

### Per-Skill Config

- `enabled`: Toggle the skill on/off
- `apiKey`: Secret input for the skill's primary API key
- `env`: Environment variables to inject when the skill runs
- `config`: Custom configuration passed to the skill

### Load Config

- `watch`: Watch skill directories for changes (hot-reload)
- `watchDebounceMs`: Debounce delay for watch events (default 250ms)
- `extraDirs`: Additional directories to scan for skills

## How Skills Get Into the System Prompt

1. At session start, OpenClaw takes a **snapshot** of all eligible skills
2. The snapshot is cached for performance (not recomputed per turn)
3. `formatSkillsForPrompt()` converts skills into system prompt text
4. The formatted text is inserted into the **Skills** section of the system prompt
5. Token cost: ~195 base tokens + ~97 chars per skill

The agent sees something like:

```
## Available Skills

You have the following skills available. Use them when relevant:

- **weather**: Get current weather and forecasts for any location
- **github**: Create issues, manage PRs, review code
- **apple-notes**: Read and write Apple Notes
```

Plus the full skill instructions from the markdown body.

## Built-In Skills (43+)

| Skill | What It Does |
|-------|-------------|
| `1password` | 1Password CLI integration |
| `apple-notes` | Apple Notes read/write |
| `apple-reminders` | Apple Reminders management |
| `bear-notes` | Bear Notes integration |
| `blogwatcher` | Monitor RSS/blog feeds |
| `camsnap` | Camera snapshot capture |
| `canvas` | Visual workspace (React) |
| `clawhub` | ClawHub skill marketplace |
| `coding-agent` | Spawn coding subagent |
| `discord` | Discord-specific actions |
| `gemini` | Google Gemini features |
| `gh-issues` | GitHub Issues management |
| `github` | GitHub automation |
| `healthcheck` | System health monitoring |
| `himalaya` | Himalaya email CLI |
| `imsg` | iMessage send/read |
| `mcporter` | MCP server integration |
| `model-usage` | Token usage reporting |
| `notion` | Notion workspace access |
| `obsidian` | Obsidian vault operations |
| `openai-image-gen` | DALL-E image generation |
| `openai-whisper` | Audio transcription |
| `openai-whisper-api` | Whisper API transcription |
| `openhue` | Philips Hue lighting |
| `oracle` | Database query tool |
| `peekaboo` | Screenshot analysis |
| `session-logs` | Session transcript access |
| `sherpa-onnx-tts` | Local TTS via Sherpa-ONNX |
| `skill-creator` | Create new skills |
| `slack` | Slack-specific actions |
| ... | And more |

## CLI Commands

```bash
openclaw skills list              # List all eligible skills
openclaw skills list --eligible   # Only show skills that pass gating
openclaw skills info weather      # Show skill details
openclaw skills check             # Validate all skills
```

## Swift Replication Notes

1. **Skill format**: Parse YAML frontmatter + markdown body
2. **Gating**: Check platform, binaries (via `which`), env vars, config
3. **Loading**: Scan directories in priority order
4. **Hot-reload**: Use `DispatchSource.makeFileSystemObjectSource` for file watching
5. **System prompt injection**: Append skill descriptions to the prompt
6. **Start with**: A few essential skills (apple-notes, github, session-logs)
