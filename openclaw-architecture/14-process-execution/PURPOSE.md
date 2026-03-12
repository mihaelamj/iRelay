# Process Execution — Purpose

## Why This System Exists

Process execution lets the agent **run commands on the host machine** — executing shell commands, running scripts, building projects, and interacting with system tools. It's one of the most powerful (and dangerous) capabilities.

## The Problem It Solves

1. **Tool execution**: When the agent decides to run `npm test` or `grep -r "TODO"`, something needs to actually spawn that process, capture its output, and return the result. That's this system.

2. **Interactive shells**: Some commands need a real terminal (PTY) — tools that detect terminal capabilities, interactive prompts, or programs that use cursor movement. The PTY adapter provides this.

3. **Safety and timeout**: Runaway processes need to be killed. Two independent timeouts (overall execution time and inactivity/no-output) catch both slow commands and hung processes. Process tree termination (SIGTERM → grace → SIGKILL) ensures child processes don't linger.

4. **Cross-platform**: Windows handles processes differently (no process groups, .cmd files need cmd.exe routing, different signal handling). The system abstracts these differences behind a unified adapter interface.

## What iRelay Needs from This

iRelay's process execution needs the two-adapter pattern (PTY for interactive, child for direct), the dual-timeout system (overall + no-output), and the process tree kill sequence (SIGTERM → grace period → SIGKILL to process group). On macOS, the PTY allocation and process group management are the key pieces.

## Key Insight for Replication

Process execution is a **supervised spawn with streaming output**. The core is: spawn a process, stream its stdout/stderr to the caller in real-time, enforce timeouts, and clean up the process tree when done. The approval workflow (which commands require human approval) is a separate security concern layered on top.
