# CLI — Purpose

## Why This System Exists

The CLI is the **operator's control panel**. It lets you set up OpenClaw, manage configuration, check health, list sessions, install plugins, and perform every administrative task from the terminal.

## The Problem It Solves

1. **Setup and onboarding**: First-time users need a guided path through API key configuration, channel setup, and agent customization. The CLI provides interactive wizards for this.

2. **Headless operation**: Not every deployment has a web UI. Servers, containers, and SSH sessions need a terminal interface for all management tasks.

3. **Scriptability**: Every command supports `--json` output for automation. CI/CD pipelines, monitoring scripts, and custom tooling can parse structured output.

4. **Fast startup**: With 40+ commands, loading them all on every invocation would be slow. Lazy loading ensures only the invoked command's module is imported.

## What iRelay Needs from This

iRelay uses Swift Argument Parser instead of Commander.js, but the command structure should mirror OpenClaw's: setup, config (get/set/apply), agent management, skills, plugins, health, sessions, and models. The `--json` output mode is important for tooling integration.

## Key Insight for Replication

The CLI is a **thin wrapper** around the gateway and config APIs. Most commands just call gateway methods or read/write config files. The main value is in the user experience: clear help text, interactive prompts, and formatted output.
