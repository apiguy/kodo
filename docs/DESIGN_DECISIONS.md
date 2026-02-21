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
security invariants, and process-level sandboxing (planned).

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

### Desktop GUI (planned)

Cross-platform desktop interface for managing the daemon. Requirements:
- Native installers for macOS, Windows, Linux
- Small binary size
- Setup wizard, permission manager, audit log viewer

Technology TBD.

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

### Why Not Rust FFI for Security?

Originally planned a Rust FFI layer (`kodo-gate`) as a security boundary.
Decided against it for several reasons:

1. **The FFI boundary doesn't prevent bypass.** Ruby has full OS access
   (`system()`, `File.open`, `Net::HTTP`). A malicious skill in the same
   process can skip the gate entirely. The gate only works if the code
   *can't* do anything without it — which requires process-level sandboxing
   regardless.
2. **Contributor friction.** Requiring a Rust toolchain to build a Ruby gem
   contradicts the "lightweight & portable" goal.
3. **The hard problems are Ruby-side.** Capability token design, permission
   scoping, user approval flows, manifest generation — these are all
   application-level concerns, not systems programming.
4. **Process isolation solves enforcement better.** OS-level sandboxing
   (separate processes with dropped capabilities) is a stronger boundary
   than FFI and doesn't require a second language.

kodo-gate is now a pure Ruby module that handles policy decisions
(should this be allowed?) while process-level sandboxing handles
enforcement (make sure it can't do anything else).

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
Telegram, CLI, and a desktop GUI all connected to the same running daemon
with shared conversation history and state.

### Channels Are Adapters

Every messaging platform implements the same interface: `connect!`, `poll`,
`send_message`, `disconnect!`. Messages are normalized to `Kodo::Message`
before entering the router. Adding a new platform means implementing one
class — the router, memory, and LLM don't know or care where messages
come from.

### Skill Security Model

Skills are the primary attack surface. A skill claims to do one thing but
could do anything once executed — the LLM invokes it based on a description,
not by inspecting the code. This is exactly how Cisco caught OpenClaw skills
exfiltrating data.

Kodo's approach is defense in depth across three layers:

#### Layer 1: LLM-Powered Code Audit

At install time (and on every update), the skill's source code is analyzed
by the user's own configured LLM. The audit:

- Compares declared capabilities against what the code actually does
- Flags discrepancies (e.g., a weather skill making unexpected network calls)
- Detects obfuscation, eval(), dynamic requires, remote code loading
- Generates a **capability manifest**: what the skill needs (network domains,
  filesystem paths, process spawning, etc.)
- Presents a human-readable summary for user approval

The user's own LLM key pays for this — no centralized inference cost.

Known limitations:
- Prompt injection via skill metadata/comments could manipulate the auditor
- Delayed payloads (clean code that fetches real behavior at runtime)
- Subtle data exfiltration via legitimate-looking requests

These are mitigated by Layer 2.

#### Layer 2: Process-Level Sandboxing

Skills run as **separate processes**, not in the main Ruby process. The
sandbox enforces the capability manifest generated in Layer 1:

- Network: only declared domains, all other outbound blocked
- Filesystem: only declared paths, everything else denied
- No eval, no shelling out unless explicitly declared
- Resource limits (memory, CPU, duration) via OS-level controls
- IPC with the main agent through a restricted protocol

This is the actual enforcement — the audit tells you what the skill *should*
need, the sandbox ensures that's all it *can* do. Neither is sufficient
alone, but together they're strong.

Implementation: `fork` + `Process.setrlimit` + dropped capabilities on
Linux. Platform-specific sandboxing strategies for macOS/Windows.

#### Layer 3: Signature Verification

Skills are cryptographically signed. The signature is checked:
- At install time (was this tampered with since it was published?)
- At load time (was this tampered with on disk?)
- On update (diff-scoped audit — only analyze what changed, flag new
  capabilities requested)

### Skill Marketplace Architecture

Three-tier trust model:

**Verified tier** (hosted on kodo.bot):
- Manually reviewed + LLM audit by maintainers
- Full static analysis pipeline
- Highest trust signal
- Small, curated catalog

**Community tier** (open registry):
- Automated static analysis on submission (AST parsing, dependency
  scanning, network call detection — free, no LLM cost)
- Signature storage and verification
- Trust scoring (download counts, user reports, age)
- LLM audit happens at install time on the user's machine, not centralized

**Local/unregistered skills:**
- Installed from git repos or local files
- Full LLM audit at install time (user's LLM key)
- No marketplace trust signal — user assumes responsibility

Cost control strategy:
- Static analysis is free and runs on all tiers
- Centralized LLM audit only for verified tier (maintainers control volume)
- Community/local skill auditing runs on the user's machine with their key
- Cache audit results by code hash — don't re-audit unchanged code
- Rate limit submissions per author on the community tier

## Roadmap

### Implemented
- Ruby daemon with heartbeat loop
- Multi-provider LLM via RubyLLM
- Telegram channel adapter
- Console channel for CLI chat
- Composable prompt assembly (persona.md, user.md, pulse.md, origin.md)
- File-based conversation memory with optional AES-256-GCM encryption
- Knowledge store (long-term facts with remember/forget tools)
- Sensitive data redaction (regex + LLM-assisted via utility model)
- Audit logging

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
- Domain-specific skills (wealth management, customer support, etc.)
- Third-party data integrations
- Skill marketplace at kodo.bot

## Current State

The foundation is complete. The daemon is functional with:

- `PromptAssembler` with layered security hierarchy
- `Router` wired to RubyLLM with conversation memory and knowledge tools
- `Heartbeat` loop with configurable interval
- Telegram channel adapter (direct API, no gem dependency)
- Console channel for CLI chat
- File-based memory store with optional AES-256-GCM encryption
- Knowledge store for long-term facts (remember/forget via LLM tools)
- Sensitive data redaction (regex patterns + LLM-assisted classification)
- Daily audit logs (JSONL)
- CLI with start, chat, memories, init, status, version, help
- Full RSpec test suite

**Next milestone:** Security layer (kodo-gate, skill sandboxing).

## Conventions

- Ruby 3.2+, no Rails
- `Data.define` for value objects
- Zeitwerk autoloading
- RSpec for tests
- Secrets via environment variables, referenced by `_env` suffix in config
- All config in `~/.kodo/config.yml`
- All prompt files in `~/.kodo/*.md`
- Audit trail in `~/.kodo/memory/audit/YYYY-MM-DD.jsonl`
