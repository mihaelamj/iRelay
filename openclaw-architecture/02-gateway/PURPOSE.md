# Gateway — Purpose

## Why This System Exists

The gateway is the **central nervous system** of OpenClaw. It's a WebSocket server that every component connects to — the Control UI, CLI tools, channel adapters, and remote nodes all communicate through the gateway.

## The Problem It Solves

Without a gateway, every component would need direct connections to every other component. The gateway provides:

1. **Single control plane**: One WebSocket endpoint that all clients connect to. Want to send a chat message, change config, or check health? It all goes through the gateway.

2. **Real-time events**: The gateway pushes events (new messages, health updates, presence changes) to all connected clients. No polling needed.

3. **Authentication & authorization**: Device pairing, token-based auth, and scope-based permissions ensure only authorized clients can control the system.

4. **Backpressure**: Slow clients don't block fast ones. The gateway detects slow consumers and either drops non-essential events or disconnects them.

## What SwiftClaw Needs from This

SwiftClaw's `ClawGateway` package needs to implement the same WebSocket protocol (JSON frames with req/res/event types), the same challenge-based authentication handshake, and the same event broadcasting with scope guards. The exact frame format matters because any Control UI needs to speak the same protocol.

## Key Insight for Replication

The gateway is stateless between requests — it doesn't store conversations or config. It's purely a **router and multiplexer**. All persistent state lives in the session store, config files, and memory databases. This makes it straightforward to implement: parse frames, dispatch to handlers, broadcast events.
