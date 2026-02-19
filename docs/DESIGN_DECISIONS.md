# Design Decisions & Context

> Handoff document from the initial design session. Read alongside CLAUDE.md
> and ARCHITECTURE.md for full project context.

## What Is Kodo?

Kodo is an open-source, security-first AI agent framework in Ruby. It
competes with OpenClaw (150k+ GitHub stars, formerly ClawdBot/MoltBot)
but addresses critical security gaps that Cisco's AI security team and
others have documented.

Kodo is designed as an open-source engine that can power commercial products.
The architecture supports white-labeling and extension for domain-specific
use cases (wealth management, customer support, etc.).

## Naming Journey

The name went through extensive exploration due to trademark conflicts:

- **Pulse** — reserved for a commercial product
- Pulseworks, PulseForge, Pulsestream, Pulseway — all taken by existing companies
- Loopwork — taken by an AI agent company (direct competitor)
- Pulseloop — frontrunner until the domain proved unavailable
- **Kodo** (鼓動) — Japanese for "heartbeat, drum movement" (KOH-DOH, two
  syllables with long "o" sounds). Associated with the famous Kodo taiko
  drumming group — powerful, rhythmic, precisely timed beats. Perfect
  metaphor for the agent's heartbeat loop.
- **Domain acquired:** kodo.bot

## Why Not OpenClaw?

OpenClaw has massive adoption but serious security problems:

1. **No skill vetting** — Cisco found a third-party skill performing data
   exfiltration and prompt injection without user awareness. Skills are
   community-submitted with no cryptographic verification.
2. **All-or-nothing permissions** — no capability-based access control. A
   skill either has full access or no access.
3. **Prompt injection vulnerable** — SOUL.md contents are injected directly
   into the system prompt with no sanitization. Malicious content in user-
   editable files can rewrite agent behavior.
4. **No sandboxing** — skills run in the same process with full access to
   the host system.
5. **Node.js only** — limits the contributor ecosystem and makes the
   security surface area larger.

Kodo addresses each of these with: signed skills, capability-based
permissions, sandboxed execution, a layered prompt system with immutable
security invariants, and a planned Rust security gate (Phase 2).

## What We Learned From OpenClaw's Prompt System

OpenClaw's best idea is composable prompt assembly from markdown files:
SOUL.md (personality), USER.md (user context), MEMORY.md (long-term facts),
HEARTBEAT.md (idle tick instructions), BOOTSTRAP.md (first-run onboarding).

We adopted this pattern but with **deliberate differentiation** in naming
and a critical security improvement:

| OpenClaw      | Kodo          | Why the rename                                   |
|---------------|---------------|--------------------------------------------------|
| SOUL.md       | persona.md    | More accurate — it's a persona, not a soul       |
| USER.md       | user.md       | Same — generic enough                            |
| HEARTBEAT.md  | pulse.md      | "Pulse" is what happens on each heartbeat beat   |
| BOOTSTRAP.md  | origin.md     | Avoids overloaded CS term; fits the narrative     |
| MEMORY.md     | memory/       | Directory-based, already different implementation |

**The security improvement:** Kodo's `PromptAssembler` enforces a strict
hierarchy where hardcoded security invariants (Layer 1) can never be
overridden by user-editable files (Layers 2-4). OpenClaw has no such
separation — SOUL.md instructions can effectively override anything.

## Technology Choices

### Ruby Core (not Rails)

The agent daemon is pure Ruby with minimal dependencies. No Rails, no
ActiveRecord. The daemon needs to be lean and fast-starting. Dependencies:
zeitwerk (autoloading), ruby_llm (multi-provider LLM), async (event loop),
thor (CLI).

### RubyLLM for Multi-Provider Support

Initially built a hand-rolled Anthropic HTTP client. Replaced it with
[RubyLLM](https://rubyllm.com) which provides a unified API for 13+
providers (OpenAI, Anthropic, Gemini, DeepSeek, Ollama, OpenRouter, etc.)
with only 3 dependencies (Faraday, Zeitwerk, Marcel).

Users configure whichever providers they want in `config.yml` and set env
vars. Switching from Claude to GPT to a local Ollama model is a one-line
config change. This is a major differentiator vs OpenClaw which technically
supports multiple models but is heavily optimized for Claude.

### Tauri (Rust) for Desktop GUI (Phase 3)

Cross-platform installer and GUI using Tauri. Gives us:
- Native installers for macOS, Windows, Linux
- Tiny binary size vs Electron
- Shared Rust crate for security-critical operations (permissions, crypto)
- The Rust `kodo-gate` permission broker lives in this layer

### Telegram First (not WhatsApp)

The goal was "chat with Kodo from your phone." WhatsApp was the initial
target but has serious friction for open-source distribution:

- **Official WhatsApp Cloud API** requires a WhatsApp Business account for
  every user. Acceptable for a company product, dealbreaker for open-source.
- **Unofficial WhatsApp libraries** (whatsapp-web.js, Baileys) are
  JavaScript-only. No Ruby gems exist. Would require a Node.js sidecar
  process, adding a non-Ruby dependency to the project.

**Telegram Bot API** is the clear winner for v1:
- Completely free, no business account needed
- Setup: message @BotFather → get token → paste into config (3 minutes)
- Well-maintained Ruby gem (`telegram-bot-ruby`), though we use the API
  directly via net/http to minimize dependencies
- WhatsApp can be added later as an optional channel adapter (via Node.js
  sidecar) for users who want it

### Ruby-Rust Boundary (Phase 2)

Evaluated two options:
- **Option A (chosen):** Ruby calls out to Rust via FFI/local sidecar for
  privileged operations. Rust is the gatekeeper, Ruby is the brain.
- **Option B (rejected):** Rust hosts Ruby via rutie/magnus. Would give
  tighter control but limits us to the gems that work in embedded Ruby.

Option A preserves the full CRuby + gem ecosystem while getting Rust's
security guarantees where they matter most (permission enforcement, crypto,
input sanitization).

## Architecture Decisions

### The Heartbeat Is the Product

The heartbeat loop is what makes Kodo an agent rather than a chatbot. It
fires on a configurable interval (default 60s) even when no messages are
received. Each beat: collect channel state → check schedules → build
context → decide actions → execute through permission gate → log.

This was a first-principle design decision, not bolted on. OpenClaw only
recently added their "Thinking Clock" idle cognition via a GitHub issue
manifesto. Ours is architecturally core.

### The Daemon Is the Product

CLI and GUI are just clients talking to a local HTTP/WebSocket API on port
7377. Business logic never lives in a client. This means you can have
Telegram, CLI, and the Tauri GUI all connected to the same running daemon
with shared conversation history and state.

### Channels Are Adapters

Every messaging platform implements the same interface: `connect!`, `poll`,
`send_message`, `disconnect!`. Messages are normalized to `Kodo::Message`
before entering the router. Adding a new platform means implementing one
class — the router, memory, and LLM don't know or care where messages
come from.

### Skill Sandboxing (Phase 2)

Level 1 with capability tokens: skills run as forked Ruby processes with
restricted `$SAFE` level. Can only access resources with explicit capability
tokens validated by the Rust gate. Not bulletproof but dramatically better
than OpenClaw's "skills run in the main process with full access."

## Phase Roadmap

### Phase 1 — Foundation (current, this scaffold)
- Ruby daemon with heartbeat loop
- Multi-provider LLM via RubyLLM
- Telegram channel adapter
- Console channel for CLI chat
- Composable prompt assembly (persona.md, user.md, pulse.md, origin.md)
- File-based conversation memory
- Audit logging

### Phase 2 — Security Layer
- Rust `kodo-gate` permission broker (FFI from Ruby)
- Capability-based permission model
- Encrypted memory at rest (OS keychain integration)
- Skill engine with process isolation
- Skill signing and verification
- Input sanitization (Rust layer strips injection patterns before LLM)

### Phase 3 — Desktop Experience
- Tauri GUI with setup wizard
- System tray / menu bar daemon management
- Visual permission manager
- Audit log viewer

### Phase 4 — Commercial Extensions
- Domain-specific skills (wealth management, customer support, etc.)
- Third-party data integrations
- Enterprise UI built on top of Kodo
- Skill marketplace at kodo.bot

## Current State

The scaffold is complete and ready for implementation:

- 21 files across lib/, bin/, config/, docs
- `PromptAssembler` with layered security hierarchy
- `Router` wired to RubyLLM with conversation memory
- `Heartbeat` loop with configurable interval
- Telegram channel adapter (direct API, no gem dependency)
- Console channel for CLI chat
- File-based memory store with per-conversation JSON
- Daily audit logs (JSONL)
- CLI with start, chat, init, status, version, help

**Next steps to get to a working demo:**
1. `bundle install` and verify gem resolution
2. `ruby bin/kodo init` to create ~/.kodo/ with default files
3. Set ANTHROPIC_API_KEY and TELEGRAM_BOT_TOKEN
4. Enable Telegram in config, `ruby bin/kodo start`
5. Send a message on Telegram — verify round-trip works
6. Test `ruby bin/kodo chat` for console mode
7. Edit persona.md, verify personality changes take effect

## Conventions

- Ruby 3.2+, no Rails
- `Data.define` for value objects
- Zeitwerk autoloading
- RSpec for tests (not yet scaffolded)
- Secrets via environment variables, referenced by `_env` suffix in config
- All config in `~/.kodo/config.yml`
- All prompt files in `~/.kodo/*.md`
- Audit trail in `~/.kodo/memory/audit/YYYY-MM-DD.jsonl`
