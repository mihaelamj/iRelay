# Channels — Purpose

## Why This System Exists

Channels are the **mouth and ears** of OpenClaw. They connect the agent to the outside world — receiving messages from users on Telegram, Discord, Slack, WhatsApp, and 18 other platforms, and sending responses back.

## The Problem It Solves

Each messaging platform has its own API, message format, rate limits, and quirks. Channels solve:

1. **Unified interface**: Every channel implements the same plugin contract (sendText, sendMedia, startAccount, stopAccount). The rest of the system doesn't care which platform a message came from.

2. **Text chunking**: Telegram allows 4096 characters, Discord 2000, IRC 350. The chunking system splits long responses intelligently — respecting code blocks, paragraphs, and markdown — so messages look natural on every platform.

3. **Reliable delivery**: A write-ahead queue with two-phase acknowledgment ensures messages aren't lost on crashes, and retry with exponential backoff handles transient platform failures.

4. **Health monitoring**: Channels are auto-restarted if they disconnect or go stale, with cooldowns and hourly caps to prevent restart storms.

## What iRelay Needs from This

iRelay already has 8 channels implemented. The key things to match are the chunking algorithms (paragraph-aware and markdown-aware splitting), the delivery queue pattern (write-ahead + two-phase ack), and the health monitoring state machine. The plugin interface is the contract that makes channels swappable.

## Key Insight for Replication

Channels are **adapters** in the classic design pattern sense. They translate between two worlds: the platform's native API and OpenClaw's internal message format. The simpler you keep the adapter interface, the easier it is to add new channels.
