# Infrastructure — Purpose

## Why This System Exists

Infrastructure provides the **foundational utilities** that every other system depends on — path management, error handling, retry policies, rate limiting, HTTP helpers, and logging. It's the plumbing that keeps everything running reliably.

## The Problem It Solves

1. **Path security**: File operations must stay within workspace boundaries. The dual-cursor path validator follows symlinks segment-by-segment and blocks traversal attacks (`../../../etc/passwd`) and symlink escapes.

2. **Retry resilience**: Network requests fail. The exponential backoff system (with jitter and provider-specific Retry-After support) handles rate limits, timeouts, and transient errors without overwhelming the target service.

3. **Rate limiting**: Outbound API calls need to respect platform limits. The fixed-window rate limiter is O(1) in both time and space, and resets lazily without background timers.

4. **Structured logging**: Debugging a multi-channel, multi-agent system requires good logs. Tagged subsystem loggers, daily rotation, size caps, and automatic secret redaction make logs useful and safe.

## What iRelay Needs from This

Most infrastructure concerns map directly to Swift equivalents: `FileManager` for paths, `URLSession` with timeout configuration for HTTP, structured concurrency with `Task.sleep` for backoff, and actor-based counters for rate limiting. iRelay's existing `IRelayLogging` package covers logging. The path boundary checker is the most important piece to replicate carefully.

## Key Insight for Replication

Infrastructure is **boring but critical**. Each utility is simple in isolation (a rate limiter is just a counter, a retry is just a loop with sleep), but together they make the difference between a system that works reliably in production and one that breaks under real-world conditions.
