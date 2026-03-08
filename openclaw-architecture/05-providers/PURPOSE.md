# Providers — Purpose

## Why This System Exists

Providers connect OpenClaw to LLM APIs — Anthropic, OpenAI, Google, Ollama, and 20+ others. They handle the specifics of each API: how to format requests, parse streaming responses, manage authentication, and recover from failures.

## The Problem It Solves

Each LLM provider has a different API, authentication scheme, and error behavior. Providers solve:

1. **API abstraction**: Whether you're calling Claude, GPT-4, Gemini, or a local Ollama model, the agent runtime sees the same streaming interface. Providers translate to/from each API's format.

2. **Auth profile rotation**: If one API key hits a rate limit or auth error, the system automatically switches to the next profile with exponential backoff cooldowns (60s → 5min → 25min → 1hr). This keeps the agent running even when individual keys have issues.

3. **Model autodiscovery**: OpenClaw probes local servers (Ollama, vLLM) to find available models automatically, inspecting context windows and capabilities.

4. **Streaming**: SSE and NDJSON streams are parsed incrementally, with partial content pushed to the UI and channels in real-time as the LLM generates.

## What SwiftClaw Needs from This

SwiftClaw's provider packages (`ClawAnthropicProvider`, `ClawOpenAIProvider`, etc.) need to implement the same streaming interfaces, auth rotation with cooldown math (60s × 5^(n-1)), and model resolution. The SSE parsing (line-by-line with buffering) and token usage tracking are also critical for feature parity.

## Key Insight for Replication

Providers are **stateless request transformers** with one piece of state: the auth profile rotation. The core job is: take a model + messages + tools → build the right HTTP request → parse the streaming response → yield content deltas + usage. Auth rotation wraps around that.
