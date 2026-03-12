# OpenClaw Architecture Documentation

This folder contains a complete, detailed breakdown of the OpenClaw project — the TypeScript/Node.js personal AI assistant that iRelay aims to replicate in pure Swift.

Each subfolder documents one major system. Read them in order for a full understanding, or jump to any system you need.

## Table of Contents

| # | Folder | System | What It Covers |
|---|--------|--------|----------------|
| 01 | [01-overview](01-overview/) | Project Overview | What OpenClaw is, tech stack, monorepo layout, high-level architecture |
| 02 | [02-gateway](02-gateway/) | Gateway (WebSocket Server) | The control plane — WebSocket protocol, frames, auth, routing, health |
| 03 | [03-agents](03-agents/) | Agent Runtime | How AI agents run — config, system prompts, tools, streaming, subagents |
| 04 | [04-channels](04-channels/) | Messaging Channels | All 22 channels — abstraction, lifecycle, message flow, per-channel details |
| 05 | [05-providers](05-providers/) | LLM Providers | All 20+ providers — interface, SSE streaming, auth profiles, failover |
| 06 | [06-sessions](06-sessions/) | Session Management | Session model, isolation, transcripts, compaction, write locks |
| 07 | [07-memory](07-memory/) | Memory & Embeddings | Vector search, embedding providers, hybrid search, temporal decay |
| 08 | [08-cli](08-cli/) | CLI Commands | 40+ commands, Commander.js architecture, command tree |
| 09 | [09-skills](09-skills/) | Skills Platform | SKILL.md format, gating, loading, workspace skills |
| 10 | [10-plugins](10-plugins/) | Plugin/Extension System | Plugin SDK, hooks, discovery, lifecycle, 42 extensions |
| 11 | [11-voice-and-media](11-voice-and-media/) | Voice & Media | TTS/STT providers, media pipeline, format handling |
| 12 | [12-cron-and-scheduling](12-cron-and-scheduling/) | Cron & Scheduling | One-shot jobs, recurring jobs, heartbeat, delivery |
| 13 | [13-browser](13-browser/) | Browser Control | CDP Chrome automation, profiles, client actions |
| 14 | [14-process-execution](14-process-execution/) | Process Execution | PTY support, approval workflows, sandboxing |
| 15 | [15-security](15-security/) | Security Model | DM policies, pairing, allowlists, sandbox modes |
| 16 | [16-config](16-config/) | Configuration System | openclaw.json schema, validation, migration |
| 17 | [17-infrastructure](17-infrastructure/) | Infrastructure | Paths, errors, HTTP utilities, retry policies, logging |
| 18 | [18-storage](18-storage/) | Storage & Persistence | JSONL transcripts, SQLite, credential storage, file structure |

## How to Use This Documentation

1. **Start with 01-overview** to understand the big picture
2. **Read 02-gateway** to understand the central nervous system
3. **Read 03-agents** to understand how AI responses are generated
4. **Read 04-channels** to understand how messages flow in and out
5. **Then read any other system** based on what you're building

## Source Repository

The original OpenClaw source lives at: `/Users/mm/Developer/personal/public/openclaw`

## Key Numbers

- **22 messaging channels** (9 core + 13 extensions)
- **20+ LLM providers** (OpenAI, Anthropic, Google, Ollama, and more)
- **43+ built-in skills** (Apple Notes, GitHub, Obsidian, etc.)
- **42 extension plugins** (channels + features)
- **40+ CLI commands** with subcommands
- **76 src/ subdirectories** in the main codebase
- **298 infrastructure files** alone
