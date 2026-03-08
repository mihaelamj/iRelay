# SwiftClaw MVP — Scope Definition

## The MVP in One Sentence

**Talk to AI via iMessage — quick questions get instant answers, coding tasks spawn real agents (Claude Code, Codex) that work on your machine.**

## Must Have

### 1. iMessage Channel — Full Bidirectional
- **Inbound**: Poll `~/Library/Messages/chat.db` for new messages
- **Inbound media**: Detect and extract image/video/file attachments from chat.db
- **Outbound text**: Already works (AppleScript)
- **Outbound media**: Send images/files via AppleScript with POSIX file paths
- **Deduplication**: Track last-seen message ID to avoid re-processing

### 2. WhatsApp Channel — Full Bidirectional
- **Inbound text**: Already works (webhook)
- **Inbound media**: Parse image/video/document/audio webhook message types, download via Media API
- **Outbound text**: Already works (REST API)
- **Outbound media**: Upload and send images/documents via Media API
- **Webhook**: Already has verification + routing

### 3. Multimodal Message Pipeline
- `MessageContent` already has the cases — make them flow end-to-end
- `ChatMessage.content` must become multimodal (content blocks, not plain string)
- Provider layer must send images to Claude's vision API / OpenAI's vision
- Channel layer must handle media in both directions

### 4. Dual Mode: Chat + Agent Spawning

**Direct Chat (default)**:
- Quick questions, explanations, brainstorming → direct Claude/OpenAI API call
- Fast (~1-3s), no subprocess, uses the existing provider pipeline
- Multimodal: images analyzed via Claude Vision / OpenAI Vision

**Agent Spawning (on demand)**:
- Coding tasks that need file access, git, terminal → spawn Claude Code / Codex
- Triggered by: explicit prefix (`code:`, `agent:`), or keywords (`fix`, `build`, `refactor`, `run tests`)
- Spawn Claude Code via `claude -p --output-format stream-json`
- Spawn Codex via `codex exec`
- Stream output back through the message pipeline
- Working directory control (point agent at a specific project)
- Timeout enforcement (don't let agents run forever)
- Session tracking (resume conversations with the same agent)

### 5. Config Loading
- Read `~/.swiftclaw/config.json`
- `${VAR}` environment variable substitution
- Validate required fields (at minimum: which channel, which agent CLI path)

## Should Have

### 6. Multiple Agent Support
- Route "use codex for this" vs "use claude for this" based on message prefix or config
- Default agent with ability to override per-message

### 7. Progress Streaming
- Don't wait for the agent to finish — stream intermediate updates to iMessage
- "Working on it..." → "Found the issue in Storage.swift..." → "Fixed. Here's the diff..."

### 8. Error Recovery
- Retry on transient failures (API errors, agent crashes)
- Graceful error messages back to iMessage ("Agent failed, retrying...")
- SIGTERM/SIGINT clean shutdown

## Won't Have (Post-MVP)

- Browser control
- Cron/scheduling
- Skills/plugins
- Voice/TTS
- Vector memory
- Device pairing / security
- Web UI
- macOS/iOS app targets
- Telegram, Slack, Discord, Signal, Matrix, IRC (they exist but not MVP focus)
- Auto-intent classification (MVP uses explicit triggers, not AI-based routing)

## The MVP User Stories

### Quick Chat
```
You iMessage: "What's the difference between actor and class in Swift?"
SwiftClaw replies in 2 seconds with a clear explanation.
```

### Coding Task
```
You iMessage: "code: fix the failing test in Storage"
SwiftClaw spawns Claude Code → it finds the bug → fixes it → replies with the diff.
```

### Visual Context
```
You iMessage a screenshot + "code: fix this layout bug"
SwiftClaw saves the image → spawns Claude Code with the image path →
agent analyzes → makes the fix → replies with what changed.
```

## Success Criteria

1. Send a question via iMessage → fast LLM response arrives in iMessage
2. Send "code: fix X" via iMessage → Claude Code spawns → result arrives in iMessage
3. Send an image via iMessage → agent/LLM receives and analyzes it → reply arrives
4. Same flows work via WhatsApp
5. Agent output streams as multiple messages (not one giant blob at the end)
6. Sessions persist — "continue what you were doing" works
7. Survives restarts without losing conversation state
