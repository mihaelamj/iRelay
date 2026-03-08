# Coding Agent Spawner

## What This Is

The core new capability of SwiftClaw. Instead of being an LLM chat relay (send message to Claude API, return response), SwiftClaw **spawns real coding agents** — Claude Code, Codex, Gemini CLI — as subprocesses and streams their output back to the user's iMessage/WhatsApp.

## Why Spawn Instead of API

| Approach | Pros | Cons |
|----------|------|------|
| Direct API (current) | Simple, fast | No file access, no tools, no git, no terminal |
| Spawn CLI agent | Full coding capability, file editing, git, tests | Process management, streaming complexity |

The whole point of SwiftClaw is that the agent can **do things on your machine**. Claude Code already knows how to edit files, run tests, use git, manage projects. We don't need to reimplement that — we spawn it.

## Supported Agents

### Claude Code (Primary)

```bash
# Non-interactive with streaming JSON output
claude -p "Fix the failing test" \
    --output-format stream-json \
    --model sonnet \
    --working-dir /path/to/project \
    --allowed-tools "Bash(git:*) Edit Read Glob Grep" \
    --max-budget-usd 5.00

# Resume a previous session
claude --session-id <uuid> -p "Continue"
claude --continue -p "Now run the tests"

# With system prompt customization
claude -p "prompt" --system-prompt "You are a Swift expert"

# With MCP servers
claude -p "prompt" --mcp-config '{"mcpServers":{...}}'
```

**Stream JSON output** (one JSON object per line):
```json
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I'll fix that test..."}]}}
{"type":"tool_use","name":"Edit","input":{"file_path":"Tests/StorageTests.swift",...}}
{"type":"tool_result","tool_use_id":"...","content":"File edited successfully"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done. The test now passes."}]}}
{"type":"result","result":"Fixed the failing assertion in StorageTests.swift...","session_id":"abc-123"}
```

### OpenAI Codex (Secondary)

```bash
# Non-interactive execution
codex exec "Refactor the networking layer"
codex exec "Fix this" -i screenshot.png

# With config overrides
codex -c model="o3" exec "prompt"
codex -c timeout=600 exec "prompt"
```

### Others (Future)

- Gemini CLI: Similar `--non-interactive` pattern
- Aider: `aider --message "prompt" --yes`
- Custom: Any CLI that accepts a prompt and writes to stdout

## Architecture

### New Package: `AgentSpawner`

```
Packages/Sources/AgentSpawner/
├── AgentSpawner.swift          // Main actor, spawn + manage
├── AgentType.swift             // Enum of supported agent CLIs
├── AgentSession.swift          // Tracks a running agent
├── AgentStreamEvent.swift      // Output events
├── CLIBuilder.swift            // Builds Process args per agent type
└── StreamParser.swift          // Parses stdout into events
```

### Key Types

```swift
/// Which agent CLI to spawn
public enum AgentType: String, Sendable, Codable {
    case claude
    case codex
    case custom
}

/// Configuration for spawning an agent
public struct AgentSpawnConfig: Sendable {
    public let type: AgentType
    public let workingDirectory: URL
    public let model: String?
    public let systemPrompt: String?
    public let allowedTools: [String]?
    public let timeout: TimeInterval       // default: 300s
    public let budgetUSD: Double?          // cost cap
    public let sessionID: String?          // resume existing session
    public let customExecutable: String?   // for .custom type
}

/// Events streamed from a running agent
public enum AgentStreamEvent: Sendable {
    case text(String)                      // Agent's text response
    case toolUse(name: String, input: String)  // Agent is using a tool
    case toolResult(String)                // Tool output
    case progress(String)                  // Status update
    case error(String)                     // Error message
    case done(summary: String, sessionID: String)  // Agent finished
}

/// A running agent session
public struct AgentSession: Sendable {
    public let id: UUID
    public let agentType: AgentType
    public let startedAt: Date
    public let workingDirectory: URL
    public let processID: Int32
}
```

### The Spawner Actor

```swift
public actor AgentSpawner {
    private var activeSessions: [UUID: (Process, Task<Void, Never>)] = [:]

    /// Spawn an agent and stream its output
    public func spawn(
        prompt: String,
        config: AgentSpawnConfig,
        attachments: [Attachment] = []
    ) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let process = try buildProcess(prompt: prompt, config: config)
                let sessionID = UUID()

                // Set up stdout streaming
                let outPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = Pipe()

                // Feed attachments via stdin if supported (Codex -i flag, etc.)
                if !attachments.isEmpty {
                    try prepareAttachments(attachments, for: process, config: config)
                }

                try process.run()
                activeSessions[sessionID] = (process, Task.current)

                // Stream output line by line, parse into events
                let fileHandle = outPipe.fileHandleForReading
                for try await line in fileHandle.bytes.lines {
                    let event = parseEvent(line, agentType: config.type)
                    continuation.yield(event)
                }

                process.waitUntilExit()
                activeSessions.removeValue(forKey: sessionID)

                if process.terminationStatus == 0 {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: AgentError.nonZeroExit(process.terminationStatus))
                }
            }
        }
    }

    /// Cancel a running agent
    public func cancel(_ sessionID: UUID) {
        guard let (process, task) = activeSessions.removeValue(forKey: sessionID) else { return }
        process.terminate()  // SIGTERM
        task.cancel()
        // Grace period → SIGKILL handled by timeout
    }

    /// List active agent sessions
    public var active: [AgentSession] { ... }
}
```

### Attachment Handling

When the user sends an image via iMessage, how does it reach the coding agent?

```
iMessage image → InboundMessage(.image(Data, "image/png"))
    → ServiceOrchestrator saves to temp file
    → AgentSpawner includes in prompt or as CLI flag

Claude Code: Write image to temp file, reference in prompt:
    "The user sent an image (saved at /tmp/swiftclaw/img_abc.png). Analyze it."
    Claude Code will use its Read tool to view the image.

Codex: Use -i flag:
    codex exec "Fix this layout" -i /tmp/swiftclaw/img_abc.png
```

For links and videos:
- **Links**: Include URL directly in the prompt text
- **Videos**: Save to temp, reference path (agent can screenshot frames if needed)

## Integration with Message Pipeline

```
User (iMessage): "Add dark mode" + screenshot.png
         │
         ▼
IMessageChannel.pollNewMessages()
    → InboundMessage(content: .compound([.text("Add dark mode"), .image(data, "image/png")]))
         │
         ▼
ServiceOrchestrator.handleInbound()
    ├── Save image to /tmp/swiftclaw/img_abc.png
    ├── Build prompt: "Add dark mode\n[Image: /tmp/swiftclaw/img_abc.png]"
    ├── Determine agent: config.defaultAgent → .claude
    │
    ▼
AgentSpawner.spawn(prompt, config: .claude(workingDir: projectDir))
    │
    ├── Spawns: claude -p "Add dark mode..." --output-format stream-json --working-dir /project
    │
    ├── Stream event: .text("I'll analyze the screenshot and add dark mode...")
    │   → Orchestrator → iMessage: "I'll analyze the screenshot and add dark mode..."
    │
    ├── Stream event: .toolUse("Edit", "Sources/Settings/SettingsView.swift")
    │   → Orchestrator → iMessage: "Editing SettingsView.swift..."
    │
    ├── Stream event: .text("Done. Added dark mode toggle and color scheme support.")
    │   → Orchestrator → iMessage: "Done. Added dark mode toggle and color scheme support."
    │
    └── Stream event: .done(summary: "...", sessionID: "abc-123")
         → Orchestrator stores sessionID for potential "continue" later
```

## Progress Streaming Strategy

Don't dump everything to iMessage. Coalesce events:

```swift
actor ProgressCoalescer {
    private var buffer: [AgentStreamEvent] = []
    private var lastSentAt: Date = .distantPast
    private let minInterval: TimeInterval = 2.0  // Don't spam faster than 2s

    /// Buffer events, emit when meaningful
    func add(_ event: AgentStreamEvent) -> OutboundMessage? {
        switch event {
        case .text(let t):
            // Always send text (it's the agent's actual response)
            return makeMessage(t)

        case .toolUse(let name, _):
            // Coalesce rapid tool uses into periodic updates
            let now = Date()
            if now.timeIntervalSince(lastSentAt) >= minInterval {
                lastSentAt = now
                return makeMessage("Using \(name)...")
            }
            return nil

        case .done(let summary, _):
            return makeMessage(summary)

        case .error(let msg):
            return makeMessage("Error: \(msg)")

        default:
            return nil
        }
    }
}
```

## Session Persistence

Store agent session IDs so users can say "continue" or "keep going":

```swift
// In Storage/SQLite
CREATE TABLE agent_sessions (
    id TEXT PRIMARY KEY,
    channel_id TEXT NOT NULL,
    sender_id TEXT NOT NULL,
    agent_type TEXT NOT NULL,
    agent_session_id TEXT,      -- Claude Code's session ID
    working_directory TEXT NOT NULL,
    created_at REAL NOT NULL,
    last_active_at REAL NOT NULL,
    status TEXT NOT NULL        -- active, completed, failed
);
```

When user says "continue" or "keep going", look up last session and pass `--continue` or `--session-id` to Claude Code.

## Concurrency Limits

Don't let users spawn unlimited agents:

```swift
public actor AgentSpawner {
    private let maxConcurrent = 3
    private let maxPerUser = 1  // MVP: one agent at a time per sender

    public func spawn(...) throws -> AsyncThrowingStream<...> {
        guard activeSessions.count < maxConcurrent else {
            throw AgentError.tooManyActiveAgents
        }
        // ...
    }
}
```

## Error Handling

| Failure | Response |
|---------|----------|
| Agent CLI not found | "Claude Code not installed. Run: brew install claude-code" |
| Non-zero exit | "Agent failed (exit code N). Try again or use a different agent." |
| Timeout | "Agent timed out after 5 minutes. The task may be too large." |
| Budget exceeded | "Reached the $5 budget limit. Increase in config to continue." |
| Permission denied | "Agent needs access to /path. Check file permissions." |
