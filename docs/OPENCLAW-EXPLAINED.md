# How OpenClaw Works — Explained Simply

Imagine you have a really smart robot friend who can talk to you through any app you like — Telegram, Discord, iMessage, whatever. That robot can also think using different brains (AI models). OpenClaw is the system that makes all of that work. Let's walk through every piece.

---

## The Big Picture

OpenClaw is like a **post office for conversations**.

- People send messages from different apps (Telegram, Discord, Slack...)
- The post office receives all those messages in one place
- It figures out which "brain" (AI) should answer
- The brain thinks and writes a reply
- The post office sends the reply back through the same app

That's it. Everything else is just details about how each part of the post office works.

---

## Layer 1: The Front Door (Gateway)

The **Gateway** is the front door of the post office. It's a server that runs on your computer and listens for incoming messages.

**What it does:**
- Opens a door (a network port) and waits for connections
- When someone connects, it checks: "Are you allowed in?" (authentication)
- It speaks a specific language (protocol) — every message has a type, an ID, and content
- It keeps track of who's connected and whether they're still there (heartbeat)

**Think of it like:** The receptionist at a building. They check your badge, point you to the right room, and keep track of who's in the building.

**Three kinds of messages it handles:**
1. **Requests** — "Hey, please do this thing" (like sending a message to the AI)
2. **Responses** — "Here's the answer to what you asked"
3. **Events** — "Something happened!" (like the AI typing a response word by word)

---

## Layer 2: The Mailboxes (Channels)

A **Channel** is a connection to one messaging app. Each app (Telegram, Discord, etc.) is a different channel.

**What every channel must do:**
- **Connect** — log into the app and start listening for messages
- **Disconnect** — log out and stop listening
- **Receive messages** — when someone sends a message in that app, grab it
- **Send messages** — when the AI has a reply, send it back through the app
- **Report its status** — "I'm connected", "I'm disconnected", "Something went wrong"

**Each channel is different because each app works differently:**
- Telegram: You get a "bot token" from BotFather, then ask Telegram "any new messages?" over and over
- Discord: You connect to Discord's live stream and listen for events as they happen
- iMessage: You talk to the Messages app on your Mac directly
- IRC: You open a raw network connection and speak a very old text protocol

**But from the post office's point of view, they all look the same.** A message came in. It has: who sent it, which app it came from, and what they said. That's all the post office needs to know.

**Channels also handle:**
- **Security** — who's allowed to talk to the bot? (allowlist, pairing approval, open)
- **Formatting** — each app has different rules for bold text, links, message length
- **Threading** — some apps have reply threads, some don't
- **Actions** — edit a sent message, delete it, add a reaction
- **Multiple accounts** — you can have more than one bot on the same app

---

## Layer 3: The Sorting Room (Sessions)

When a message arrives at the post office, it needs to go to the right conversation. That's what **Sessions** do.

**What a session is:**
A session is one ongoing conversation. It remembers:
- Which person is talking
- Which app they're using
- Which AI brain is answering
- Everything that's been said so far (the history)

**How sessions work:**
1. A message arrives: "Hi!" from user 12345 on Telegram
2. The system looks up: "Do I have an existing conversation with user 12345 on Telegram?"
3. If yes → add this message to that conversation's history
4. If no → start a new conversation

**Why sessions matter:**
Without sessions, the AI would have no memory. Every message would be like talking to a stranger. Sessions let the AI say "Oh right, we were talking about recipes earlier!"

**Session keys** identify each conversation uniquely:
- Simple: just the agent name (one conversation per agent)
- Complex: agent + group + account + channel (many separate conversations)

---

## Layer 4: The Brains (LLM Providers)

An **LLM Provider** is a connection to one AI brain. OpenClaw can talk to many different brains:
- Claude (from Anthropic)
- ChatGPT (from OpenAI)
- Gemini (from Google)
- Ollama (runs on your own computer, no internet needed)
- And more...

**What every provider must do:**
- **Accept a conversation** — take the message history and generate a response
- **Stream the response** — send the answer back word by word (not all at once)
- **Support tools** — the AI can ask to DO things (search the web, run code, etc.)
- **List available models** — tell the system which AI models it offers

**Why streaming matters:**
Imagine ordering food. Would you rather:
- (A) Wait 30 seconds, then get the entire meal at once
- (B) Get each dish as soon as it's ready

Streaming is option B. The AI sends each word as it thinks of it, so you see the answer appearing in real time. Much better experience.

**How the AI uses tools:**
Sometimes the AI needs to DO something, not just talk. For example:
1. You ask: "What's the weather in Zagreb?"
2. The AI thinks: "I need to check the weather. Let me use the weather tool."
3. The AI sends a **tool call**: "Please run the weather tool for Zagreb"
4. The system runs the tool and gets the result: "15 degrees, cloudy"
5. The result goes back to the AI
6. The AI writes: "It's 15 degrees and cloudy in Zagreb right now!"

---

## Layer 5: The Manager (Agents)

An **Agent** is a personality for the AI. Think of it like giving the AI a job description.

**What an agent defines:**
- **System prompt** — instructions that tell the AI how to behave ("You are a helpful cooking assistant. You only talk about food.")
- **Which brain to use** — Claude, ChatGPT, Gemini, etc.
- **Which model** — like picking the smart one vs the fast one
- **Which tools** — what the AI is allowed to do (browse the web? run code? nothing?)
- **Thinking level** — how hard should the AI think? (quick answer vs deep reasoning)

**You can have multiple agents:**
- "Chef" agent that only talks about cooking, uses Claude
- "Coder" agent that helps with programming, uses ChatGPT
- "Local" agent that works offline, uses Ollama

**Agent routing** decides which agent handles each message. Maybe Telegram messages go to the Chef agent, and Discord messages go to the Coder agent.

---

## Layer 6: The Reply Desk (Auto-Reply & Delivery)

Once the AI has an answer, it needs to get back to the person who asked. This is the **delivery system**.

**What it handles:**
- **Chunking** — Discord only allows 2000 characters per message. If the AI writes 5000 characters, the system splits it into 3 messages automatically. Each app has different limits.
- **Queuing** — if multiple replies need to go out, they wait in line
- **Retry** — if sending fails (network hiccup), try again with a short wait
- **Format conversion** — the AI writes in one format, but each app needs it differently (Telegram uses HTML, Discord uses Markdown, etc.)

---

## Layer 7: The Filing Cabinet (Storage)

The system needs to remember things between restarts. That's **storage**.

**What gets stored:**
- **Sessions** — all conversation histories
- **Configuration** — which channels are set up, which providers, API keys
- **Memory** — things the AI should remember long-term (like your preferences)

**How it stores things:**
- Configuration goes in one settings file
- Each conversation is saved as its own file
- Long-term memory uses a small local database with search capability

**Why this matters:**
If you restart the system, everything picks up where it left off. Your conversations aren't lost. Your settings aren't gone.

---

## Layer 8: The Lockbox (Secrets)

API keys, bot tokens, passwords — these are **secrets**. They need special handling.

**What the secrets system does:**
- Stores credentials safely (not in plain text)
- Loads them from environment variables or secure storage
- Makes them available to channels and providers when needed
- Never shows them in logs or error messages

**Example:**
Your Telegram bot token is `123456:ABC-DEF`. The system stores this securely, and when the Telegram channel starts up, it asks: "Give me the Telegram token" and gets it from the lockbox.

---

## Layer 9: The Memory Room (Memory & Search)

Regular session history is short-term — it's the current conversation. But what if the AI needs to remember something from weeks ago?

**What the memory system does:**
- **Stores knowledge** — facts, preferences, past conversations
- **Searches by meaning** — not just exact words, but what you MEANT
- **Two search methods:**
  1. **Keyword search** — find messages containing specific words
  2. **Meaning search** — find messages about similar topics (even if different words are used)

**Example:**
You told the AI "I'm allergic to peanuts" three weeks ago. Today you ask "Can I eat pad thai?" The memory system finds the peanut allergy note (because pad thai often contains peanuts) even though the words are completely different.

---

## Layer 10: The Scheduler (Cron)

Sometimes you want the AI to do things on a schedule, not just when you message it.

**What the scheduler does:**
- Run tasks at specific times ("Every morning at 8am, send me a weather summary")
- Repeat tasks ("Every hour, check my email")
- One-time future tasks ("Remind me about the meeting at 3pm")

---

## Layer 11: The Control Panel (Admin)

You need a way to manage everything — add channels, change settings, check what's running. That's the **admin system**.

**What admin operations exist:**
- **Channel management** — add/remove channels, enable/disable them, test connections
- **Provider management** — add/remove AI providers, set default provider, test connections
- **Agent management** — create/edit agents, change system prompts, assign models
- **Session management** — list conversations, search history, delete old ones
- **Configuration** — change any setting, import/export settings
- **Status** — see what's running, what's healthy, what's broken
- **Doctor** — automatically find and fix configuration problems

**Important rule:** All admin operations are just logic — no buttons, no screens. They return plain data. Then any app (phone app, desktop app, web page) can show that data however it wants.

---

## Layer 12: The Plugin System (Extensions)

What if someone wants to add a new channel that OpenClaw doesn't support? Or a new AI provider? That's what **plugins** do.

**What can be extended:**
- **New channels** — connect to any messaging app
- **New providers** — connect to any AI brain
- **New tools** — give the AI new abilities
- **Hooks** — run custom code when certain things happen (message received, message sent, etc.)
- **New memory backends** — store memory differently

**How plugins work:**
1. Someone writes a plugin following the rules (the plugin interface)
2. They publish it or put it in a local folder
3. You install it: "Add this plugin"
4. The system discovers it and loads it
5. Now it works alongside everything else

---

## How It All Fits Together

Here's what happens when you send "What's for dinner?" on Telegram:

```
1. You type "What's for dinner?" in Telegram
         │
         ▼
2. Telegram Channel receives the message
   - Normalizes it (strips bot mentions, extracts user ID)
   - Checks security (are you on the allowlist?)
         │
         ▼
3. Session Manager finds your conversation
   - Loads your message history
   - Figures out which Agent handles Telegram messages
         │
         ▼
4. Agent prepares the request
   - Adds system prompt ("You are a helpful chef...")
   - Picks the right brain (Claude)
   - Includes conversation history
         │
         ▼
5. Claude Provider sends everything to the AI
   - Streams the response word by word
         │
         ▼
6. Auto-Reply Dispatcher formats the answer
   - Checks: is it under 4000 characters? (Telegram limit)
   - If too long, splits into multiple messages
         │
         ▼
7. Telegram Channel sends the reply
   - Uses the Telegram Bot API to deliver the message
         │
         ▼
8. You see "How about pasta carbonara?" in Telegram

9. Session Manager saves the conversation
   - Your question + the AI's answer added to history
```

---

## The Layers, Summarized

| Layer | Name | One-Line Description |
|-------|------|---------------------|
| 1 | **Gateway** | The front door — receives all connections |
| 2 | **Channels** | Mailboxes — one per messaging app |
| 3 | **Sessions** | Sorting room — tracks each conversation |
| 4 | **Providers** | Brains — connections to AI models |
| 5 | **Agents** | Managers — personality + rules for the AI |
| 6 | **Delivery** | Reply desk — formats and sends answers back |
| 7 | **Storage** | Filing cabinet — remembers everything |
| 8 | **Secrets** | Lockbox — keeps passwords safe |
| 9 | **Memory** | Memory room — long-term knowledge + search |
| 10 | **Scheduler** | Clock — runs tasks on a timer |
| 11 | **Admin** | Control panel — manage everything |
| 12 | **Plugins** | Extensions — add new capabilities |

---

## Rules That Apply Everywhere

1. **Each piece does one job.** The channel doesn't know about AI. The provider doesn't know about Telegram. They only talk through the layers above and below them.

2. **Everything looks the same from the inside.** Whether a message came from Telegram or Discord, by the time it reaches the session manager, it's just: who sent it, what they said, when they said it.

3. **The AI answer goes back the same way it came.** If you asked on Telegram, you get the answer on Telegram. If you asked on Discord, you get it on Discord.

4. **Nothing is hardcoded to one app or one AI.** You can swap Claude for ChatGPT. You can add Signal and remove Slack. The system doesn't care — it just routes messages.

5. **Admin logic has no UI.** All management operations return plain data. Any screen (phone, desktop, web) can display it however it wants.

6. **Secrets never leak.** API keys and tokens are stored securely and never appear in logs or error messages.
