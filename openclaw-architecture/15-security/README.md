# 15 — Security Model

Security in OpenClaw controls who can talk to the agent, what the agent can do, and how credentials are protected.

## DM (Direct Message) Policies

When someone sends you a DM through a messaging channel, OpenClaw checks if they're allowed:

### Policy Types

| Policy | Who Can DM | Security Level |
|--------|-----------|---------------|
| `"owner"` | Only the account owner | Highest |
| `"allowlist"` | Only explicitly listed users | High |
| `"pairing"` | Users who have paired via QR code | Medium |
| `"open"` | Anyone | Lowest (risky) |
| `"disabled"` | Nobody | Blocked |

### Configuration

```json
{
  "channels": {
    "discord": {
      "dm": {
        "policy": "allowlist",
        "allowFrom": ["123456789", "user:987654"]
      }
    },
    "signal": {
      "dm": {
        "policy": "allowlist",
        "allowFrom": ["+1234567890"]
      }
    }
  }
}
```

### Access Decision Flow

```
1. Is this a DM or group message?
   ↓
2. For DMs: Check DM policy
   - "owner" → Is sender the owner? (check allowFrom)
   - "allowlist" → Is sender in the list?
   - "pairing" → Has sender completed pairing?
   - "open" → Always allow
   - "disabled" → Always block
   ↓
3. For groups: Check group policy
   - "allowlist" → Is this group configured?
   - "open" → Allow all groups
   - "disabled" → Block all groups
   ↓
4. Return: "allow", "block", or "pairing" (needs to pair first)
```

## Group Policies

Control which groups/channels the agent responds in:

```json
{
  "channels": {
    "discord": {
      "groupPolicy": "allowlist",
      "guilds": {
        "GUILD_ID": {
          "requireMention": true,
          "channels": ["#general", "#dev"],
          "users": ["USER_ID"],
          "tools": {
            "allowlist": ["weather"],
            "denylist": ["exec"]
          }
        }
      }
    }
  }
}
```

### Per-Group Controls

- **Which channels**: Restrict to specific channels within a group
- **Which users**: Only respond to certain users in the group
- **Which tools**: Limit which tools the agent can use in this group
- **Mention required**: Whether @bot mention is needed to activate

## Device Pairing

For mobile and desktop apps, OpenClaw uses cryptographic device pairing:

### Pairing Flow

1. User generates a QR code on the gateway
2. New device scans the QR code
3. Device sends its public key to the gateway
4. Gateway verifies and stores the public key
5. Future connections are authenticated via signature

### Pairing Store

- Pending pairings stored in `pairing-pending` files
- Approved devices stored in the pairing store
- Ephemeral pairing tokens with expiry
- Per-user verification with signatures

## Tool Policy

Controls which tools the agent can use:

### Policy Levels

1. **Agent-level**: `agents.main.tools.allow/deny`
2. **Group-level**: Per-group tool allowlist/denylist
3. **Owner-only tools**: Some tools restricted to the device owner
4. **Sandbox restrictions**: Some tools blocked in Docker

### Tool Groups

```
"group:core": [read, write, edit, exec, ...]
"group:dangerous": [exec, process]
"group:external": [web_search, web_fetch]
"group:messaging": [message, slack, telegram, ...]
"group:plugins": [custom plugin tools]
```

## Execution Approval

When the agent tries to run shell commands, approval workflows can gate execution:

1. Agent requests: `exec("rm -rf /tmp/data")`
2. OpenClaw evaluates against approval rules
3. If approval needed: `exec.approval.requested` event sent
4. User approves or denies via CLI/app
5. Result returned to agent

## Owner-Only Operations

Some operations are restricted to the device owner:
- Gateway control commands
- Cron job management
- WhatsApp login
- Configuration changes
- Channel start/stop

## Key Implementation Files

| File | Purpose |
|------|---------|
| `src/security/dm-policy-shared.ts` | DM policy evaluation |
| `src/security/` | 31 security files |
| `src/pairing/` | Device pairing system |

## Swift Replication Notes

1. **DM policy**: Simple enum-based policy check
2. **Allowlists**: Store as arrays in configuration
3. **Device pairing**: Use CryptoKit for keypair generation and signature verification
4. **Keychain**: Use SwiftClaw's existing `ClawSecurity` package
5. **Tool policy**: Filter tool arrays based on policy config
