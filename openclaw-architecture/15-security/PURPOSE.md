# Security — Purpose

## Why This System Exists

Security controls **who can talk to the agent and what it can do**. It prevents unauthorized access, restricts dangerous operations, protects sensitive data, and sandboxes file system access.

## The Problem It Solves

1. **Access control**: Not everyone should be able to message your AI agent. DM policies (disabled, open, pairing, allowlist) control who can initiate conversations, with separate rules for direct messages and group chats.

2. **Device trust**: The device pairing system uses public-key cryptography to establish trusted devices. Paired devices get tokens with scoped permissions (read, write, admin), and token verification uses timing-safe comparison to prevent side-channel attacks.

3. **Command safety**: The agent can run arbitrary shell commands, which is powerful but dangerous. The approval workflow requires human confirmation for dangerous tools, with allowlist pattern matching for auto-approved safe commands.

4. **Data protection**: API keys and tokens must never leak into logs, error messages, or LLM context. Secret redaction strips sensitive values from config snapshots, and external content wrapping prevents prompt injection from untrusted sources (emails, webhooks).

## What iRelay Needs from This

iRelay's `IRelaySecurity` package needs the DM policy decision tree (the three-mode gate), device pairing (Ed25519 key storage + token rotation), the command approval flow (two-phase registration + human decision), and the file system boundary checker (dual-cursor path validation with symlink following). Secret redaction should use pattern matching for known API key formats.

## Key Insight for Replication

Security in OpenClaw is **defense in depth** — multiple layers that each catch different threats. Access control stops unauthorized users. Tool policies stop dangerous tool use. Approval workflows add human oversight. Path boundaries stop file system escapes. Secret redaction stops data leaks. No single layer is sufficient alone.
