# Sessions — Purpose

## Why This System Exists

Sessions are the **memory of each conversation**. They track who's talking, what was said, and where the conversation left off. Without sessions, every message would start a brand-new conversation with no context.

## The Problem It Solves

1. **Conversation continuity**: Sessions map a channel + user combination to a persistent conversation. Your Telegram chat with the bot picks up where it left off, even after restarts.

2. **Context management**: LLMs have finite context windows. When a conversation grows too long, the compaction system summarizes old messages into a concise summary, preserving key decisions, tasks, and identifiers while fitting within the window.

3. **Thread branching**: When someone starts a thread (Discord thread, Telegram topic), the system forks the parent session's context into an isolated thread session, so threads have their own conversation history.

4. **Concurrency safety**: Multiple messages can arrive simultaneously. File locks with PID-based staleness detection prevent corruption, and the session store uses atomic writes to ensure consistency.

## What SwiftClaw Needs from This

SwiftClaw's `ClawSessions` package needs the JSONL transcript format (append-only, one JSON per line), the session store (JSON with normalized keys and 45-second cache), and the compaction algorithm (3-tier: full summary → partial → minimal fallback). The context pruning system (soft trim tool results, then hard clear) is important for long conversations.

## Key Insight for Replication

Sessions are a **dual-store system**: metadata (sessions.json) for fast lookups and routing, and transcripts (.jsonl files) for the actual conversation history. This separation means you can quickly find and route to a session without loading its entire history.
