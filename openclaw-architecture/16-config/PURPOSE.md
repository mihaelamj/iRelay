# Configuration — Purpose

## Why This System Exists

Configuration controls **everything about how OpenClaw behaves** — which channels are active, which LLM models to use, agent behavior, security policies, session settings, and more. All of this lives in a single JSON file with a robust loading pipeline.

## The Problem It Solves

1. **Single source of truth**: One file (`openclaw.json`) configures the entire system. No scattered config files, no environment-variable-only settings, no hidden defaults. Everything is explicit and version-controllable.

2. **Environment variable substitution**: Secrets like API keys shouldn't be hardcoded. The `${VAR}` syntax lets config reference environment variables, with `.env` file support and missing-var warnings.

3. **Safe updates**: Config changes at runtime use merge-patch semantics (RFC 7396) with prototype pollution protection. The hot-reload system preserves `${VAR}` references when writing back — you never lose your variable references.

4. **Migration**: As OpenClaw evolves, config fields get renamed or restructured. Idempotent migrations automatically upgrade old configs without user intervention, and each migration checks for its source field rather than relying on version numbers.

## What iRelay Needs from This

iRelay's config system (Codable JSON in `~/.irelay/`) needs the same `${VAR}` substitution, Zod-equivalent validation (Swift's Codable + custom validators), merge-patch semantics for partial updates, and the include directive system for splitting config across files. The 12-step loading pipeline is the reference implementation.

## Key Insight for Replication

Config loading is a **pipeline of transformations**: read file → parse JSON5 → resolve includes → apply env vars → substitute `${VAR}` → validate schema → apply defaults → normalize paths. Each step is independent and testable. The hot-reload pattern (runtime snapshot + source snapshot + diff) is clever but optional for an initial implementation.
