# SwiftClaw MVP

## The Vision

**Talk to AI coding agents via iMessage. Send text, images, links, videos. SwiftClaw spawns real coding agents (Claude Code, Codex, etc.) and streams their work back to you.**

You're on the couch. You iMessage your bot: "Add dark mode to the settings screen" with a screenshot. SwiftClaw spawns Claude Code in your project directory, streams its progress, and replies with what it did. You review on your phone. Done.

## What This Is NOT

This is not a general-purpose AI chat relay. This is not OpenClaw-but-in-Swift. SwiftClaw is a **coding agent orchestrator** that you control from iMessage (and WhatsApp).

## Documents

| File | What It Covers |
|------|---------------|
| [VISION.md](VISION.md) | Product purpose — why SwiftClaw exists |
| [CURRENT-STATE.md](CURRENT-STATE.md) | What's already built |
| [MVP-DEFINITION.md](MVP-DEFINITION.md) | Exact scope — must/should/won't have |
| [MVP-WORKSTREAMS.md](MVP-WORKSTREAMS.md) | Implementation plan with dependencies |
| [CHANNEL-REFACTOR.md](CHANNEL-REFACTOR.md) | Channel protocol redesign for multimodal + extensibility |
| [AGENT-SPAWNER.md](AGENT-SPAWNER.md) | How coding agents get spawned and controlled |

## The Gap

SwiftClaw has a working message pipeline (channel → session → provider → response → channel). What's missing:

1. **Multimodal channel protocol** — current `MessageContent` is text-only in practice
2. **iMessage inbound** — polling `chat.db` is stubbed
3. **Coding agent spawner** — the core new capability
4. **WhatsApp media** — only handles text today

## Critical Path

```
Channel Refactor (multimodal) ──→ iMessage Inbound ──→ Agent Spawner ──→ Ship
         │                                                    │
         └──→ WhatsApp Media ─────────────────────────────────┘
```
