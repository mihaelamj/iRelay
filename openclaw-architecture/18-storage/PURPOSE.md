# Storage & Persistence — Purpose

## Why This System Exists

Storage handles **how data survives** across restarts, crashes, and concurrent access. Every piece of persistent state — config, sessions, transcripts, memory, credentials, logs — goes through the storage layer.

## The Problem It Solves

1. **Crash safety**: The atomic write pattern (write to temp file → rename) ensures that a crash mid-write never corrupts the original file. Readers always see either the complete old file or the complete new file.

2. **Concurrent access**: Multiple processes or async operations may try to write the same file. Write locks with PID-based staleness detection (including PID recycling checks) prevent corruption, and a watchdog timer force-releases locks held too long.

3. **Append-only transcripts**: JSONL files are perfect for conversation transcripts — each message is one line, appended atomically. Reading is just splitting on newlines and parsing each line. No need for a database for the conversation log.

4. **Credential security**: Auth profiles, API keys, and OAuth tokens need secure storage with lock-protected writes. The storage layer handles file permissions (0o600 for files, 0o700 for directories) and atomic operations.

## What SwiftClaw Needs from This

SwiftClaw should use `FileManager.replaceItem(at:withItemAt:)` for atomic writes on macOS, `flock()` for file locks, GRDB/SQLite for memory and potentially sessions (better query support than JSON), and Keychain via `ClawSecurity` for credentials (more secure than JSON files). The JSONL format for transcripts can be read/written with `FileHandle`.

## Key Insight for Replication

Storage in OpenClaw follows one principle: **never leave data in an inconsistent state**. Atomic writes prevent partial files. Locks prevent concurrent corruption. Append-only logs prevent data loss. Deep-copy on cache reads prevents mutation bugs. Every pattern serves this principle.
