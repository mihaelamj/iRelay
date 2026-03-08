# Plugins — Purpose

## Why This System Exists

Plugins let developers **extend every aspect** of OpenClaw with code — adding new tools, channels, LLM providers, hooks into the message pipeline, custom CLI commands, and background services. They're the deep customization layer.

## The Problem It Solves

1. **Modular architecture**: Not everything belongs in the core. Voice calls, browser automation, and specialized memory backends are plugins that can be installed, updated, or removed independently.

2. **Hook-based interception**: Plugins can intercept and modify behavior at 24 points in the pipeline — before the LLM is called, after a tool runs, when a message is about to be sent, etc. This enables monitoring, transformation, and custom logic without forking the core.

3. **Priority ordering**: When multiple plugins hook into the same event, priority determines execution order. Higher priority plugins run first and can set values that lower-priority plugins see. Concatenation fields (like context) get contributions from all plugins.

4. **Safe discovery and loading**: Plugins are security-checked (symlink escape, world-writable dirs, UID ownership) during discovery, and config schemas are validated via JSON Schema on load.

## What SwiftClaw Needs from This

SwiftClaw's plugin system needs the hook dispatch pattern (void hooks in parallel, modifying hooks sequentially), the priority ordering, and the plugin lifecycle (discover → load → register → activate). The 24 hook names define the integration surface — these are the points where plugins can intercept behavior.

## Key Insight for Replication

Plugins are **hooks + registrations**. A plugin registers things (tools, channels, hooks) during load, and the system calls those registrations at the right time. The Plugin SDK is just the API surface that plugins call to register themselves. Keep the registration API simple and the hook points well-defined.
