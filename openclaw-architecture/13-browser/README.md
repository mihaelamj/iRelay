# 13 — Browser Control

OpenClaw can control a Chrome/Chromium browser via the **Chrome DevTools Protocol (CDP)**. This lets the agent browse the web, fill out forms, take screenshots, and interact with web applications.

## Architecture

The browser system has 130+ files and provides:
- Chrome/Chromium process management
- CDP connection and command execution
- User data directory management
- Extension installation
- Cookie and storage state management

## Chrome Executable Discovery

OpenClaw finds Chrome on different platforms:

| Platform | Paths Checked |
|----------|--------------|
| macOS | `/Applications/Google Chrome.app`, bundled Chrome in OpenClaw.app |
| Linux | `google-chrome`, `chromium-browser`, Snap paths |
| Windows | Registry, Program Files |

## CDP Integration

### What Is CDP?

Chrome DevTools Protocol is a JSON-RPC protocol that lets you control Chrome programmatically. It's the same protocol that Chrome DevTools uses.

### Connection Flow

1. Launch Chrome with `--remote-debugging-port`
2. Connect via WebSocket to `ws://127.0.0.1:{port}`
3. Send JSON-RPC commands
4. Receive responses and events

### Available Actions

**Core Actions:**
- `navigate(url)`: Go to a URL
- `goto(url)`: Alias for navigate
- `reload()`: Refresh the page
- `screenshot()`: Capture the page as an image

**Observation Actions:**
- DOM inspection
- Accessibility tree traversal
- Element selection and querying

**State Actions:**
- Get/set cookies
- Get/set localStorage
- Get/set sessionStorage
- Manage browser storage

**URL Actions:**
- Get current URL
- Navigate history (back/forward)

## Browser Sessions

Each browser session has:
- A unique session ID
- A Chrome process with its own user data directory
- A CDP connection
- Extension state
- Cookie/storage state

## CLI Commands

```bash
openclaw browser start           # Launch browser session
openclaw browser stop            # Shutdown
openclaw browser list            # Show active sessions
openclaw browser inspect <id>    # Debug CDP connection
openclaw browser resize <w>x<h>  # Set viewport size
openclaw browser manage          # Configuration management
openclaw browser state           # Get/set browser state
```

## Key Implementation Files

| File | Purpose |
|------|---------|
| `src/browser/cdp.ts` | CDP protocol client |
| `src/browser/chrome.ts` | Chrome executable discovery |
| `src/browser/client-actions-core.ts` | Navigate, screenshot |
| `src/browser/client-actions-observe.ts` | DOM inspection |
| `src/browser/client-actions-state.ts` | Cookies, storage |

## Swift Replication Notes

1. **WebKit**: Consider using WKWebView instead of Chrome for Apple-native approach
2. **CDP**: Could use Chrome CDP if cross-browser support needed
3. **Process management**: Use `Process` class to launch Chrome
4. **WebSocket**: URLSessionWebSocketTask for CDP connection
5. **Lower priority**: This is a Phase 3 feature for SwiftClaw
