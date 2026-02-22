# CLAUDE.md — Kodo Development Guide

> **First time here?** Start by reading this file, then `ARCHITECTURE.md`,
> then `docs/DESIGN_DECISIONS.md` for the full context behind every choice
> in this codebase.

## What is Kodo?

Kodo (鼓動, "heartbeat") is an open-source, security-first AI agent framework
written in Ruby. It runs as a local daemon and communicates through messaging
platforms (Telegram, Slack, etc.). The name comes from the Japanese word for
heartbeat — the core architecture is a rhythmic loop that pulses on a
configurable interval, checking for messages, running scheduled tasks, and
taking autonomous action.

## Project Structure

```
├── ARCHITECTURE.md      # System design and component details
├── CLAUDE.md            # This file — development guide for AI assistants
├── Gemfile              # Ruby dependencies
├── kodo-bot.gemspec     # Gem specification (published as kodo-bot)
├── bin/
│   └── kodo             # CLI entrypoint
├── docs/
│   └── DESIGN_DECISIONS.md  # Naming, competitive analysis, rationale
├── lib/
│   ├── kodo.rb          # Top-level module, autoloads
│   └── kodo/
│       ├── version.rb
│       ├── config.rb          # YAML config loader
│       ├── daemon.rb          # HTTP server + lifecycle
│       ├── heartbeat.rb       # Core event loop
│       ├── router.rb          # Message routing (inbox → LLM → outbox)
│       ├── llm.rb             # RubyLLM wrapper (multi-provider)
│       ├── prompt_assembler.rb # Builds system prompt from layered files
│       ├── channels/
│       │   ├── base.rb        # Abstract channel interface
│       │   ├── telegram.rb    # Telegram Bot API adapter
│       │   └── console.rb     # Direct CLI chat channel
│       ├── memory/
│       │   ├── store.rb       # Conversation persistence
│       │   ├── knowledge.rb   # Long-term fact storage (remember/forget)
│       │   ├── reminders.rb   # Scheduled reminders (add/dismiss/fire)
│       │   ├── encryption.rb  # AES-256-GCM encryption at rest
│       │   ├── redactor.rb    # Sensitive data redaction (regex + LLM)
│       │   └── audit.rb       # Action audit trail
│       ├── search/
│       │   ├── result.rb       # Search result value object
│       │   └── tavily.rb       # Tavily web search adapter
│       ├── secrets/
│       │   ├── broker.rb       # Secret access control and dispatch
│       │   └── store.rb        # Encrypted secret persistence
│       └── tools/
│           ├── prompt_contributor.rb # Mixin: tools declare capability metadata
│           ├── get_current_time.rb   # LLM tool: current date/time
│           ├── remember_fact.rb      # LLM tool: save a fact to knowledge
│           ├── forget_fact.rb        # LLM tool: remove a fact from knowledge
│           ├── recall_facts.rb       # LLM tool: search knowledge store
│           ├── update_fact.rb        # LLM tool: update a fact in place
│           ├── set_reminder.rb       # LLM tool: schedule a reminder
│           ├── list_reminders.rb     # LLM tool: list active reminders
│           ├── dismiss_reminder.rb   # LLM tool: cancel a reminder
│           ├── web_search.rb         # LLM tool: search the web via Tavily
│           ├── fetch_url.rb          # LLM tool: fetch and read a URL
│           └── store_secret.rb       # LLM tool: store an API key securely
├── config/
│   └── default.yml      # Default configuration
└── spec/                # RSpec tests
```

## Key Design Decisions

1. **The daemon is the product.** CLI and GUI are just clients talking to a
   local HTTP/WebSocket API on port 7377. Never put business logic in a client.

2. **Channels are adapters.** Every messaging platform implements the same
   interface (connect!, poll, send_message, disconnect!). Messages are
   normalized to Kodo::Message before entering the router.

3. **The heartbeat is what makes it an agent.** Without the heartbeat loop,
   this is just a chatbot. The heartbeat fires on interval even with no
   incoming messages, enabling proactive behavior.

4. **Security is a gate, not a wall.** The permission model is capability-based.
   Skills/actions declare what they need, users grant scoped tokens. Enforcement
   is via process-level sandboxing, with policy handled by kodo-gate (pure Ruby).

5. **Prompts are assembled, not hardcoded.** The system prompt is built from
   layered files in ~/.kodo/ with a strict hierarchy:
   - Layer 1: System invariants (hardcoded, non-overridable security rules)
   - Layer 2: persona.md (personality, tone — user-editable)
   - Layer 3: user.md (who the user is — user-editable)
   - Layer 4: pulse.md (idle beat instructions — user-editable)
   - Layer 5: Runtime context (model, channels, time — injected by daemon)
   User files are advisory and cannot override security invariants.

## Conventions

- Ruby 3.2+
- Use `Data.define` for value objects (Messages, Config, etc.)
- Zeitwerk autoloading via the `zeitwerk` gem
- RSpec for tests
- Standard Ruby style (rubocop with relaxed config)
- No Rails — this is a standalone daemon
- Prefer stdlib over gems when reasonable
- All config via YAML files + environment variables for secrets

## Running Locally

```bash
bundle install
export ANTHROPIC_API_KEY="your-key"
export TELEGRAM_BOT_TOKEN="your-token"
ruby bin/kodo start
```

## Common Tasks

- Add a new channel: create `lib/kodo/channels/your_channel.rb` implementing
  the `Kodo::Channels::Base` interface, register it in `config/default.yml`
- Switch LLM providers: configure the provider in `~/.kodo/config.yml` under
  `llm.providers` and set the corresponding environment variable
- Test the heartbeat: `ruby bin/kodo start --heartbeat-interval=5` for rapid
  iteration
- Add a new tool: create `lib/kodo/tools/your_tool.rb` extending `RubyLLM::Tool`,
  `extend PromptContributor` and declare capability metadata, implement `#execute`
  and `#name`, add the class to `Router::TOOL_CLASSES`, instantiate in `Router#build_tools`

## What NOT to do

- Don't add Rails or ActiveRecord — keep this lean
- Don't bypass RubyLLM — always go through Kodo::LLM.chat, never call providers directly
- Don't bypass the router — all messages flow through Kodo::Router
- Don't store secrets in config files — use _env suffix convention to read
  from environment variables
- Don't put business logic in CLI or GUI — the daemon is the product

## Further Reading

- [ARCHITECTURE.md](ARCHITECTURE.md) — system design and component details
- [docs/DESIGN_DECISIONS.md](docs/DESIGN_DECISIONS.md) — naming journey,
  competitive analysis vs OpenClaw, technology choices and rationale,
  roadmap with context
