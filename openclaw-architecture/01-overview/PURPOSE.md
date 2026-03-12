# Overview — Purpose

## Why This System Exists

OpenClaw is a **self-hosted AI assistant platform** that lets you run your own AI agent — one that can talk to you over Telegram, Discord, Slack, and 19 other channels, use tools (browse the web, run code, manage files), remember past conversations, and operate autonomously on a schedule.

## The Problem It Solves

Most AI assistants are cloud-only, locked to one chat interface, and forget everything between sessions. OpenClaw solves three problems:

1. **Multi-channel**: You shouldn't need a different AI for each messaging platform. OpenClaw connects to 22 channels and routes all conversations to the same agent with the same memory.

2. **Persistent and autonomous**: The agent remembers past conversations, can be scheduled to do things while you're away, and maintains long-running context across sessions.

3. **Self-hosted and extensible**: You control your data, your API keys, and your agent's behavior. A plugin system lets you add custom tools, channels, and behaviors.

## What iRelay Needs from This

iRelay is replicating OpenClaw in pure Swift. This overview documentation provides the **complete mental model** — what the system does, how the pieces fit together, and what the startup/request/response lifecycle looks like — so the Swift implementation can match behavior without having to reverse-engineer it from 200K+ lines of TypeScript.

## Key Insight for Replication

OpenClaw is fundamentally a **message router with an LLM brain**. Messages arrive from channels, get routed to an agent, the agent thinks and acts, and responses flow back out. Everything else (memory, skills, plugins, scheduling) is layered on top of that core loop.
