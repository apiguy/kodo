# Kodo Architecture

> **Kodo** (鼓動, "heartbeat") — an open-source, security-first AI agent framework written in Ruby.

## Overview

Kodo is an autonomous AI agent that runs locally on your hardware and communicates
through messaging platforms you already use. Unlike cloud-hosted AI assistants, Kodo
keeps your data on your machine, encrypts memory at rest, and enforces capability-based
permissions on every action.

**Design principles:**
- Security first — every action goes through a permission gate
- Local first — your data stays on your hardware
- Channel agnostic — messaging platforms are pluggable adapters
- CLI and GUI are equal citizens — the daemon is the product, interfaces are clients

## System Architecture

```
┌──────────────────────────────────────────────────────┐
│                    User Interfaces                    │
│                                                      │
│   ┌─────────────┐   ┌─────────────┐   ┌──────────┐  │
│   │ Desktop GUI │   │  CLI (kodo) │   │ Web Chat │  │
│   │  (future)   │   │             │   │ (future) │  │
│   └──────┬──────┘   └──────┬──────┘   └────┬─────┘  │
│          └─────────────────┼────────────────┘        │
│                            │                         │
│                 ┌──────────▼──────────┐              │
│                 │   Daemon HTTP API   │              │
│                 │  localhost:7377     │              │
│                 │  (WebSocket + REST) │              │
│                 └──────────┬──────────┘              │
├────────────────────────────┼─────────────────────────┤
│                    Agent Runtime                     │
│                                                      │
│   ┌────────────────────────▼───────────────────────┐ │
│   │              Kodo::Core                        │ │
│   │                                                │ │
│   │  ┌──────────────────────────────────────────┐  │ │
│   │  │           Heartbeat Loop                 │  │ │
│   │  │     (the "kodo" — configurable interval) │  │ │
│   │  │                                          │  │ │
│   │  │  Every beat:                             │  │ │
│   │  │   1. Collect state from channels         │  │ │
│   │  │   2. Check scheduled pulses              │  │ │
│   │  │   3. Build context window                │  │ │
│   │  │   4. Decide + act (via LLM)             │  │ │
│   │  │   5. Log to audit trail                  │  │ │
│   │  └──────────────────────────────────────────┘  │ │
│   │                                                │ │
│   │  ┌──────────┐ ┌───────────┐ ┌──────────────┐  │ │
│   │  │   LLM    │ │  Channel  │ │   Memory     │  │ │
│   │  │ Provider │ │  Manager  │ │   Store      │  │ │
│   │  └──────────┘ └───────────┘ └──────────────┘  │ │
│   │                                                │ │
│   │  ┌──────────────────────────────────────────┐  │ │
│   │  │          Skill Engine (future)           │  │ │
│   │  │     Sandboxed, signed, permissioned      │  │ │
│   │  └──────────────────────────────────────────┘  │ │
│   └────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

## Port: 7377

The daemon listens on `localhost:7377`. This port is unregistered with IANA
and easy to remember.

## Component Details

### Heartbeat Loop (`Kodo::Heartbeat`)

The core event loop that defines Kodo as an agent rather than a chatbot.
Configurable interval (default: 60 seconds). On each beat:

1. **Collect** — poll all connected channels for new messages
2. **Route** — send each message through the router and respond
3. **Reminders** — check for due reminders and deliver them to the right channel
4. **Log** — write the full beat to the audit trail

The heartbeat runs even when no messages are received. This is what makes
Kodo proactive — it can deliver reminders and (in the future) run scheduled
tasks without any user input.

### LLM Provider (`Kodo::LLM`)

Thin wrapper around [RubyLLM](https://rubyllm.com), which provides a unified
API for 13+ providers including OpenAI, Anthropic, Gemini, DeepSeek, Mistral,
Ollama, OpenRouter, and any OpenAI-compatible API.

Users configure whichever providers they want in `~/.kodo/config.yml` and set
the corresponding environment variables. Kodo passes these through to RubyLLM
at startup. Switching models is a one-line config change:

```yaml
llm:
  model: gpt-4o           # or claude-sonnet-4-6, gemini-2.5-pro, llama3:8b, etc.
  providers:
    openai:
      api_key_env: OPENAI_API_KEY
```

### Prompt Assembler (`Kodo::PromptAssembler`)

The system prompt is not a static string. It's assembled at runtime from
layered files with a strict security hierarchy:

```
┌─────────────────────────────────────────────────────┐
│  Layer 1: System Invariants (hardcoded, immutable)  │
│  - Security rules, anti-injection, core identity    │
├─────────────────────────────────────────────────────┤
│  Layer 2: persona.md (user-editable)                │
│  - Personality, tone, communication style           │
├─────────────────────────────────────────────────────┤
│  Layer 3: user.md (user-editable)                   │
│  - Who the user is, preferences, context            │
├─────────────────────────────────────────────────────┤
│  Layer 4: pulse.md (user-editable)                  │
│  - What to notice during idle heartbeat cycles      │
├─────────────────────────────────────────────────────┤
│  Layer 5: Runtime Context (injected by daemon)      │
│  - Model, channels, timestamp, capabilities         │
├─────────────────────────────────────────────────────┤
│  Layer 6: Skill Instructions (future, on-demand)    │
│  - Loaded just-in-time when a skill is invoked      │
└─────────────────────────────────────────────────────┘
```

Files live in `~/.kodo/` and are plain Markdown. Users edit them to
customize the agent. The key security property: **user-editable files are
advisory**. They shape personality and behavior but cannot override the
hardcoded invariants in Layer 1 (anti-exfiltration, anti-injection, identity
protection).

An additional file, `origin.md`, runs only during the first conversation
to onboard the user and help them set up their persona and preferences.

Each file is capped at 10,000 characters to prevent context window bloat.

### Channel Manager (`Kodo::Channels`)

Each messaging platform is a channel adapter implementing a standard interface:

```ruby
module Kodo
  module Channels
    class Base
      def connect!        # establish connection
      def disconnect!     # clean shutdown
      def poll            # check for new messages → Array<Message>
      def send_message(message) # send outbound message
      def channel_id      # unique identifier
    end
  end
end
```

Current channels: Telegram, CLI direct chat
Future: Slack, Discord, WhatsApp, Signal

### Memory Store (`Kodo::Memory`)

Conversation history and long-term agent memory. File-based storage (JSONL)
with optional AES-256-GCM encryption at rest. Structure:

```
~/.kodo/
  config.yml           # daemon configuration
  persona.md           # agent personality and tone
  user.md              # user context and preferences
  pulse.md             # idle heartbeat instructions
  origin.md            # first-run onboarding
  memory/
    conversations/     # per-channel conversation history
    knowledge/         # long-term learned facts
    reminders/         # scheduled reminders
    audit/             # action audit trail
  skills/              # installed skill definitions
```

### Tools (`Kodo::Tools`)

LLM tools give the agent the ability to take actions beyond generating text.
All tools extend `RubyLLM::Tool` and receive dependencies via constructor
injection. The router registers tools based on which stores are available.

**Always available:**
- `get_current_time` — returns current date, time, day of week, and time period

**Knowledge tools** (require knowledge store):
- `remember` — save a fact about the user
- `forget` — remove a previously remembered fact
- `recall_facts` — search knowledge by query and/or category
- `update_fact` — update a fact in place (forget + remember with same metadata)

**Reminder tools** (require reminders store):
- `set_reminder` — schedule a reminder for a future time
- `list_reminders` — show all active reminders sorted by due time
- `dismiss_reminder` — cancel a reminder by ID

**Web search tools** (require configured search provider):
- `web_search` — search the web via Tavily (rate-limited, 3/turn)
- `fetch_url` — fetch and extract text from a URL (SSRF-protected)

**Secret storage tool** (require secrets broker):
- `store_secret` — securely store an API key and activate it immediately
  without a restart; validates known key formats before storing

Tools that mutate state (remember, update_fact, set_reminder, store_secret)
enforce rate limits per turn, content length caps, and sensitive data
filtering via the Redactor. The heartbeat delivers due reminders proactively.

Each tool can optionally `extend PromptContributor` to declare its own
capability metadata (name, enabled/disabled guidance). The Router reads these
declarations to build the capabilities section of the system prompt — adding
a new tool only requires the tool file, one line in `TOOL_CLASSES`, and one
line in `build_tools`.

**Adding a new tool:** Create a class in `lib/kodo/tools/` extending
`RubyLLM::Tool`, `extend PromptContributor` and declare `capability_name` /
`enabled_guidance` if applicable, implement `#execute` and `#name`, add the
class to `Router::TOOL_CLASSES`, and instantiate it in `Router#build_tools`.

### Message Types

All messages flowing through Kodo are normalized to a common format:

```ruby
Kodo::Message = Data.define(
  :id,           # unique message ID
  :channel_id,   # which channel this came from/goes to
  :sender,       # who sent it (:user, :agent, :system)
  :content,      # text content
  :timestamp,    # Time
  :metadata      # channel-specific extras (reply_to, media, etc.)
)
```

## Configuration

```yaml
# ~/.kodo/config.yml
daemon:
  port: 7377
  heartbeat_interval: 60  # seconds

llm:
  model: claude-sonnet-4-6  # any model from your configured providers
  # utility_model: claude-haiku-4-5-20251001  # small model for background tasks
  providers:
    anthropic:
      api_key_env: ANTHROPIC_API_KEY
    # openai:
    #   api_key_env: OPENAI_API_KEY
    # ollama:
    #   api_base: http://localhost:11434

channels:
  telegram:
    enabled: true
    bot_token_env: TELEGRAM_BOT_TOKEN

memory:
  encryption: false
  passphrase_env: KODO_PASSPHRASE
  store: file

logging:
  level: info
  audit: true
```

## Roadmap

### Implemented
- Ruby daemon with heartbeat loop
- Multi-provider LLM support via RubyLLM (Anthropic, OpenAI, Gemini, Ollama, etc.)
- Telegram channel adapter
- Conversation memory (file-based, encrypted at rest)
- Knowledge store (long-term facts with remember/forget/recall/update tools)
- Reminders with proactive heartbeat delivery
- 11 LLM tools (time, knowledge CRUD, reminders CRUD, web search, secret storage)
- Web search via Tavily (SSRF-protected URL fetching, rate limiting)
- Encrypted secret storage with live activation (no restart required)
- Tool-declared prompt context via `PromptContributor` mixin
- Sensitive data redaction (regex + LLM-assisted)
- Audit logging
- CLI direct chat with thinking spinner (`kodo chat`)

### Planned — Security
- kodo-gate: capability-based permission model (pure Ruby)
- LLM-powered skill auditing at install time
- Process-level skill sandboxing (fork + resource limits)
- Skill signing and verification
- Capability manifest generation and enforcement

### Planned — Desktop Experience
- Desktop GUI with setup wizard
- System tray / menu bar daemon management
- Visual permission manager
- Audit log viewer

### Planned — Ecosystem
- Additional channel adapters (Slack, Discord, WhatsApp)
- Skill marketplace at kodo.bot
- Plugin API for custom integrations
- Multi-agent routing
