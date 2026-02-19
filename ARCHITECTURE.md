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
│   │  Tauri GUI  │   │  CLI (kodo) │   │ Web Chat │  │
│   │  (Phase 3)  │   │  (Phase 2)  │   │ (future) │  │
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

The daemon listens on `localhost:7377` ("KODO" on a phone keypad: 5-6-3-6...
close enough. Actually chosen because 7377 is unregistered and memorable.)

## Component Details

### Heartbeat Loop (`Kodo::Heartbeat`)

The core event loop that defines Kodo as an agent rather than a chatbot.
Configurable interval (default: 60 seconds). On each beat:

1. **Collect** — poll all connected channels for new messages
2. **Schedule** — check if any registered pulses (cron-like tasks) are due
3. **Context** — assemble conversation history + pending tasks + system state
4. **Reason** — send context to the LLM, get a decision
5. **Act** — execute any actions through the permission gate
6. **Log** — write the full beat to the audit trail

The heartbeat runs even when no messages are received. This is what makes
Kodo proactive — it can notice things and act on its own.

### LLM Provider (`Kodo::LLM`)

Thin wrapper around [RubyLLM](https://rubyllm.com), which provides a unified
API for 13+ providers including OpenAI, Anthropic, Gemini, DeepSeek, Mistral,
Ollama, OpenRouter, and any OpenAI-compatible API.

Users configure whichever providers they want in `~/.kodo/config.yml` and set
the corresponding environment variables. Kodo passes these through to RubyLLM
at startup. Switching models is a one-line config change:

```yaml
llm:
  model: gpt-4o           # or claude-sonnet-4-20250514, gemini-2.5-pro, llama3:8b, etc.
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

Phase 1 channels: Telegram, CLI direct chat
Future: Slack, Discord, WhatsApp (via Node.js sidecar), Signal

### Memory Store (`Kodo::Memory`)

Conversation history and long-term agent memory. Phase 1 uses file-based
storage (JSON) encrypted at rest via OpenSSL. Structure:

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
    audit/             # action audit trail
  skills/              # installed skill definitions
```

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
  model: claude-sonnet-4-20250514  # any model from your configured providers
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
  encryption: true
  store: file  # file | sqlite (future)

logging:
  level: info
  audit: true
```

## Phase Roadmap

### Phase 1 — Foundation (current)
- [x] Project scaffold
- [ ] Ruby daemon with heartbeat loop
- [ ] Multi-provider LLM support via RubyLLM (Anthropic, OpenAI, Gemini, Ollama, etc.)
- [ ] Telegram channel adapter
- [ ] Basic conversation memory (file-based)
- [ ] Audit logging
- [ ] CLI direct chat (`kodo chat`)

### Phase 2 — Security Layer
- [ ] kodo-gate: capability-based permission model (pure Ruby)
- [ ] LLM-powered skill auditing at install time
- [ ] Process-level skill sandboxing (fork + resource limits)
- [ ] Skill signing and verification
- [ ] Encrypted memory at rest
- [ ] Capability manifest generation and enforcement

### Phase 3 — Desktop Experience
- [ ] Tauri GUI with setup wizard
- [ ] System tray / menu bar daemon management
- [ ] Visual permission manager
- [ ] Audit log viewer

### Phase 4 — Ecosystem
- [ ] Additional channel adapters (Slack, Discord, WhatsApp)
- [ ] Skill marketplace at kodo.bot
- [ ] Plugin API for custom integrations
- [ ] Multi-agent routing
