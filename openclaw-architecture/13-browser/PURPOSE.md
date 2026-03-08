# Browser Automation — Purpose

## Why This System Exists

Browser automation gives the agent **eyes and hands on the web**. It can navigate to pages, read content, fill forms, click buttons, take screenshots, and interact with web applications — all through Chrome DevTools Protocol.

## The Problem It Solves

1. **Web interaction**: Some tasks require a real browser — logging into websites, filling forms, navigating SPAs, or reading JavaScript-rendered content that simple HTTP requests can't access.

2. **Visual understanding**: Screenshots let the agent see what a page looks like. Combined with accessibility tree snapshots, the agent can understand page structure and interact with specific elements by reference.

3. **Content extraction**: The agent can read page text, access localStorage/sessionStorage/cookies, and capture network responses — useful for debugging, testing, and data gathering.

4. **Safe abstraction**: Raw CDP is complex. The Playwright abstraction layer provides high-level actions (click, type, wait, fill) that map to reliable CDP operations with proper timeouts and error handling.

## What SwiftClaw Needs from This

Browser automation is one of the later features to replicate. The core need is a CDP WebSocket client (JSON-RPC over WebSocket) and the screenshot capture pipeline (capture → normalize size → return). For full interaction, the action dispatch system (click/type/wait by element reference) and accessibility snapshots are needed.

## Key Insight for Replication

Browser automation is **remote control via WebSocket**. Every operation is a JSON-RPC message sent to Chrome: "navigate here," "screenshot this," "click that element." The complexity is in making this reliable (timeouts, element references, page load detection), not in the protocol itself.
