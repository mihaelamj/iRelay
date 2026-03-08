# 04 — Messaging Channels

Channels are how OpenClaw talks to the outside world. Each channel is a plugin that connects to a messaging platform (Telegram, Slack, Discord, etc.) and translates between that platform's native format and OpenClaw's internal message format.

## The Channel Abstraction

Every channel must implement the `ChannelPlugin` interface. This is a large interface made up of many **adapters** — each adapter handles one responsibility:

```
ChannelPlugin:
  id: ChannelId                    # Unique channel identifier
  meta: ChannelMeta                # Name, docs URL, icon
  capabilities: ChannelCapabilities # What this channel can do

  # Adapters (each is optional):
  config       # Account management, enable/disable
  configSchema # Configuration validation schema
  setup        # Initial setup and credential validation
  security     # DM allowlists, group policies
  pairing      # Device pairing (QR codes, etc.)
  elevated     # Elevated privilege mode
  groups       # Group/channel management
  mentions     # Mention detection and stripping
  outbound     # Message sending (text, media, polls)
  messaging    # Message formatting and delivery
  threading    # Thread/reply support
  streaming    # Real-time streaming support
  actions      # Message actions (reactions, edits, deletes)
  status       # Health status and probing
  heartbeat    # Periodic heartbeat messages
  auth         # Authentication flows
  gateway      # Channel lifecycle (start/stop)
  directory    # User/channel discovery
  resolver     # ID resolution and normalization
  agentPrompt  # Custom agent prompt additions
  agentTools   # Channel-specific tools for the agent
```

### Key Adapters Explained

**ChannelConfigAdapter** — Manages accounts:
- `listAccountIds()`: Returns all accounts for this channel (you might have multiple Slack workspaces)
- `resolveAccount()`: Get a specific account by ID
- `isConfigured()`: Can this account send/receive? (has valid credentials)
- `isEnabled()`: Is this account turned on?

**ChannelOutboundAdapter** — Sends messages out:
- `deliveryMode`: `"direct"` (SDK calls send) or `"gateway"` (gateway handles dispatch)
- `textChunkLimit`: Max characters per message (varies by platform)
- `chunker`: Function to split long text into platform-safe chunks
- `sendText()`: Send a text message
- `sendMedia()`: Send an image, audio, video, or file
- `sendPoll()`: Send a poll/survey

**ChannelGatewayAdapter** — Runs the channel:
- `startAccount()`: Start listening for messages (launch bot, open socket)
- `stopAccount()`: Stop gracefully
- `loginWithQrStart/Wait()`: QR-based login (WhatsApp)
- `logoutAccount()`: Clear credentials

**ChannelSecurityAdapter** — Access control:
- `resolveDmPolicy()`: Who can DM? (`"open"`, `"allowlist"`, `"owner"`, `"admin"`)

## All 22 Channels

### Core Channels (in src/)

| Channel | Transport | Auth | Message Limit | Media | Threading |
|---------|-----------|------|---------------|-------|-----------|
| **Telegram** | HTTP long-poll / webhook | Bot token | 4,096 chars | Photos, docs, voice | Forum topics |
| **WhatsApp** | Baileys (Selenium) | QR code scan | 4,096 chars | Photos, docs (limited) | Quote replies |
| **Slack** | Socket Mode + REST | Bot + App token | No hard limit | File uploads | Message threads |
| **Discord** | WebSocket Gateway + REST | Bot token | 2,000 chars | Attachments, embeds | Thread channels |
| **Signal** | signal-cli REST | Phone number | Unlimited | Files, attachments | Quote replies |
| **iMessage** | Messages.framework / AppleScript | System permissions | Unlimited | Images, files | Message threads |
| **WebChat** | Built-in Hummingbird server | Session cookie | Unlimited | All formats | N/A |
| **Google Chat** | Chat API | Service account | Unlimited | Files | Threads |
| **IRC** | Raw TCP socket (NWConnection) | NickServ / none | 350 chars | None (URLs only) | None (prefix convention) |
| **LINE** | Webhook (HTTP POST) | Channel token | Platform limit | Images, rich menus | Reply tokens |

### Extension Channels (in extensions/)

| Channel | Transport | Notes |
|---------|-----------|-------|
| **BlueBubbles** | REST API | Recommended iMessage alternative |
| **Microsoft Teams** | Microsoft Graph API | Enterprise integration |
| **Matrix** | HTTP API | Open federation protocol |
| **Feishu** | Feishu API | Chinese enterprise messaging |
| **Mattermost** | WebSocket + REST | Open-source Slack alternative |
| **Nextcloud Talk** | REST API | Self-hosted collaboration |
| **Nostr** | Relay protocol | Decentralized social |
| **Synology Chat** | REST API | NAS-based messaging |
| **Tlon** | Urbit protocol | Decentralized OS messaging |
| **Twitch** | IRC (TMI) | Live streaming chat |
| **Zalo** | REST API | Vietnamese messaging |
| **Zalo Personal** | REST API | Personal Zalo variant |

## Message Flow

Here's exactly what happens when someone sends you a message:

### Inbound (User → Agent)

```
1. User sends "Hello" in Telegram
   ↓
2. Telegram bot plugin receives the update via long-polling
   ↓
3. Plugin normalizes the message:
   {
     from: "user123",
     to: "bot456",
     text: "Hello",
     chatType: "direct",      # or "group"
     messageId: "msg789",
     channel: "telegram",
     accountId: "default"
   }
   ↓
4. Gateway receives the normalized message
   ↓
5. Routing layer determines the target agent:
   - Check DM allowlist → allowed?
   - Check group policy → allowed?
   - Match against route bindings → which agent?
   - Build session key: "agent:main:dm:user123"
   ↓
6. Session manager loads/creates the session
   ↓
7. Agent runtime picks up the message (see 03-agents)
```

### Outbound (Agent → User)

```
1. Agent generates response text: "Hi there! How can I help?"
   ↓
2. Block reply emitter formats the text
   ↓
3. Outbound delivery system:
   a. Normalize payload (text, media, buttons)
   b. Select delivery channel + account
   c. Check text length against channel limit
   ↓
4. If text > channel limit, run the chunker:
   - Telegram: Split at 4,096 chars, preserve markdown
   - Discord: Split at 2,000 chars, preserve code blocks
   - IRC: Split at 350 chars, handle code fences
   ↓
5. Call plugin.outbound.sendText() for each chunk
   ↓
6. Plugin calls platform API (e.g., Telegram Bot API sendMessage)
   ↓
7. User sees the reply in Telegram
```

## Channel Configuration

Each channel is configured in `openclaw.json` under `channels.<channel-id>`:

```json
{
  "channels": {
    "telegram": {
      "enabled": true,
      "token": "123456:ABC-DEF...",
      "replyToMode": "off",
      "topics": {
        "123": {
          "agentId": "writing-agent",
          "allowFrom": ["user456"]
        }
      }
    },
    "discord": {
      "enabled": true,
      "token": "YOUR_BOT_TOKEN",
      "replyToMode": "first",
      "mediaMaxMb": 8,
      "groupPolicy": "allowlist",
      "guilds": {
        "GUILD_ID": {
          "requireMention": true,
          "channels": ["#general", "#dev"],
          "users": ["USER_ID"],
          "tools": {
            "allowlist": ["weather", "code"],
            "denylist": []
          }
        }
      },
      "dm": {
        "policy": "owner",
        "allowFrom": ["YOUR_USER_ID"]
      }
    },
    "slack": {
      "enabled": true,
      "botToken": "xoxb-...",
      "appToken": "xapp-..."
    }
  }
}
```

### Multiple Accounts

A single channel can have multiple accounts:

```json
{
  "channels": {
    "discord": {
      "accounts": {
        "work": { "token": "work-bot-token" },
        "personal": { "token": "personal-bot-token" }
      }
    }
  }
}
```

## Channel Lifecycle

### Startup

1. Gateway loads configuration
2. For each channel + account combination:
   - Check if `enabled` is true
   - Check if `configured` is true (has valid credentials)
   - Call `plugin.gateway.startAccount(ctx)` to begin listening
3. Channel sets `status.connected = true` when ready

### Running

- Provider listens for inbound messages (polling, WebSocket, or webhook)
- Each message is normalized and routed to an agent
- Outbound messages are delivered via the provider's API
- Status is tracked: connected, last error, last inbound, last outbound, active runs

### Restart on Failure

When a channel crashes:
- **Delay**: Exponential backoff (5s → 10s → 20s → ... → 5 minutes)
- **Max attempts**: 10 consecutive failures
- **Reset**: Counter resets on successful reconnection
- **Manual stop**: Prevents auto-restart

### Shutdown

- `plugin.gateway.stopAccount()` called
- Monitor/listener stops
- Status set to disconnected

## Group vs DM Handling

### Direct Messages (DMs)

- `chatType === "direct"`
- No mention required (always activates)
- Security controlled by DM policy:
  - `"owner"`: Only the account owner
  - `"allowlist"`: Only listed users
  - `"open"`: Anyone (risky)

### Group Messages

- `chatType === "group"`
- May require @mention to activate (`requireMention: true`)
- Group policy controls which groups are allowed:
  - `"allowlist"`: Only configured groups
  - `"open"`: All groups (noisy, rarely used)
- Per-group configuration: which channels, which users, which tools

## Mention Detection

Each channel has its own mention format:

| Channel | Mention Format | Example |
|---------|---------------|---------|
| Discord | `<@USER_ID>` or `<@!USER_ID>` | `<@123456789>` |
| Slack | `<@USER_ID>` | `<@U123456>` |
| Telegram | `@username` | `@mybot` |
| IRC | `nickname:` prefix | `mybot: hello` |
| Signal | None (DMs only) | N/A |

Mentions are **stripped** from outbound messages before delivery.

## Text Chunking

Long AI responses must be split for platforms with message limits:

| Channel | Limit | Chunking Strategy |
|---------|-------|-------------------|
| Telegram | 4,096 chars | Paragraph-aware, preserves markdown |
| Discord | 2,000 chars | Smart splitting, preserves code blocks |
| Slack | No hard limit | None needed |
| IRC | 350 chars | Code-fence aware |
| Signal | No hard limit | Paragraph-aware |
| WhatsApp | 4,096 chars | Paragraph-aware |

**Chunking priority**:
1. Split by paragraphs (double newlines)
2. If paragraph > limit, split by sentences
3. If sentence > limit, split by words
4. If word > limit, split by characters
5. Always preserve markdown formatting within chunks

## Extension Channel Pattern

Extension channels are **npm packages** with a specific structure:

```
extensions/discord/
├── package.json          # Must include openclaw.channel metadata
├── src/
│   ├── channel.ts        # Exports ChannelPlugin object
│   ├── runtime.ts        # Gateway logic (monitor, send)
│   ├── send.ts           # Message sending
│   └── monitor.ts        # Inbound listener
├── dist/                 # Built output
└── tsconfig.json
```

The `package.json` must declare the channel:

```json
{
  "name": "@openclaw/plugin-discord",
  "openclaw": {
    "channel": {
      "id": "discord",
      "label": "Discord",
      "blurb": "Discord Bot API integration"
    }
  }
}
```

Extensions use the **Plugin SDK** for advanced runtime features:

```typescript
import { type ChannelPlugin } from "openclaw/plugin-sdk/discord";
```

## AllowFrom Format by Channel

Different channels identify users differently:

| Channel | Format | Example |
|---------|--------|---------|
| Discord | User ID or `<@ID>` | `"123456789"`, `"user:987654"` |
| Slack | User ID or `@handle` | `"U123456"`, `"@john"` |
| Telegram | Numeric user ID | `"567890"` |
| IRC | `nick!user@host` or just `nick` | `"admin"`, `"bot!user@host.com"` |
| Signal | E164 phone number | `"+1234567890"` |
| WhatsApp | E164 phone number | `"+1234567890"` |

## Swift Replication Notes

1. **Channel protocol**: Define a Swift `Channel` protocol with actor isolation (already exists in SwiftClaw as `ChannelKit`)
2. **Adapter pattern**: Each responsibility (config, outbound, security) can be a separate protocol
3. **Plugin system**: Use Swift Package Manager dynamic libraries or a registration pattern
4. **Text chunking**: Port the markdown-aware chunker with platform-specific limits
5. **Multi-account**: Support array of accounts per channel type
6. **Lifecycle**: Use structured concurrency (TaskGroup) for channel management
