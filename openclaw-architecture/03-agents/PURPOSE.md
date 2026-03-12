# Agents — Purpose

## Why This System Exists

The agent runtime is the **brain** of OpenClaw. It receives a user message, constructs a rich context (system prompt, tools, memory, skills), calls an LLM, handles tool calls in a loop, and produces a response. This is the core intelligence layer.

## The Problem It Solves

Calling an LLM API is simple. Running a reliable, production-grade agent is not. The agent runtime solves:

1. **Dynamic context assembly**: The system prompt is built from identity files (SOUL.md), user preferences (USER.md), available tools, active skills, and memory — all assembled fresh for each turn.

2. **Tool execution loop**: The agent can call tools (run code, read files, search memory) and loop until it has an answer. This requires managing tool policies, approval workflows, and execution safety.

3. **Resilience**: Auth profiles rotate on failure, models fail over on rate limits, context compacts when it overflows, and the whole thing retries with exponential backoff. A single LLM error doesn't crash the conversation.

4. **Subagents**: Complex tasks can spawn child agents with isolated context and restricted tools, enabling parallel work with depth-limited recursion.

## What iRelay Needs from This

iRelay's `ClawAgentRuntime` needs to replicate the run loop (attempt → check result → retry/failover/compact → repeat), the system prompt assembly pipeline, and the tool policy evaluation chain. The streaming event lifecycle (message_start → message_update → tool_execution → message_end) is what the UI and channels consume.

## Key Insight for Replication

The agent runtime is essentially a **state machine with retry logic**. The core loop is: build prompt → call LLM → if tool calls, execute them and loop → if error, classify and maybe retry with different auth/model → if success, return. Everything else is supporting that loop.
