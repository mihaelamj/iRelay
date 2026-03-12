# iRelay — Vision

## Why iRelay Exists

You want to talk to coding agents from your phone. Not through a laptop browser, not through a terminal — through **iMessage**, the app you already have open.

The AI coding tools are incredible (Claude Code, Codex, Gemini CLI) but they're all terminal-bound. You have to be at your desk, in a shell, to use them. iRelay breaks that constraint.

## The Product

iRelay is a **macOS daemon** that:

1. **Receives messages via iMessage** (and WhatsApp) — text, images, screenshots, links, videos
2. **Spawns real coding agents** — Claude Code, Codex, or any CLI-based agent
3. **Streams their work back** — progress updates, diffs, results, all delivered to your chat
4. **Manages sessions** — conversations persist, agents can be resumed, context carries forward

## Core Use Cases

### 1. Code from Anywhere
You're away from your desk. You iMessage: "Fix the failing test in iRelay's Storage package." iRelay spawns Claude Code in the project directory, it finds and fixes the test, and you get the diff on your phone.

### 2. Visual Context
You screenshot a bug on your phone and send it via iMessage with "Fix this layout issue." iRelay forwards the image to the coding agent, which analyzes it and makes the fix.

### 3. Quick Tasks
"Run the tests." "What's the build status?" "Show me the last 5 commits." Quick commands that spawn a lightweight agent, get the answer, and reply.

### 4. Multi-Agent Delegation
"Use Codex to refactor the networking layer, then have Claude Code review the changes." iRelay orchestrates multiple agents sequentially or in parallel.

## Who It's For

You. A developer who wants to stay productive from anywhere, using the device already in your pocket. Not a team tool (yet). Not an enterprise product. A personal coding agent you talk to like a friend on iMessage.

## What Makes It Different

| Other AI Coding Tools | iRelay |
|-----------------------|-----------|
| Terminal-only | iMessage + WhatsApp |
| One agent at a time | Spawn and orchestrate multiple |
| Text-only input | Images, screenshots, links, videos |
| You must be at your desk | Works from your phone |
| Session dies with terminal | Sessions persist across restarts |
| Single model | Route to Claude Code, Codex, Gemini, any CLI agent |

## Design Principles

1. **iMessage-first** — Every feature must work through iMessage. If it doesn't translate to a chat message, don't build it.
2. **Spawn, don't replicate** — Don't reimplement Claude Code. Spawn it. Let the real tools do the real work.
3. **Multimodal from day one** — Images and videos are first-class. Not an afterthought bolted on later.
4. **Channel-agnostic foundation** — iMessage is primary, WhatsApp is MVP, but the abstraction supports any channel.
