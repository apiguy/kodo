# 🥁 Kodo

**Kodo** (鼓動, "heartbeat") is an open-source, security-first AI agent framework
written in Ruby. It runs locally on your hardware and communicates through the
messaging platforms you already use.

Unlike cloud-hosted AI assistants, Kodo keeps your data on your machine, enforces
capability-based permissions on every action, and gives you full control over
what your agent can and cannot do.

> **Status:** Early development — foundation is working, security layer is next.

## Quick Start

### Prerequisites

- Ruby 3.2+
- An API key for any supported LLM provider:
  [Anthropic](https://console.anthropic.com/),
  [OpenAI](https://platform.openai.com/),
  [Gemini](https://aistudio.google.com/),
  [Ollama](https://ollama.com/) (free, local), and
  [many more](https://rubyllm.com/)
- A Telegram Bot Token (message [@BotFather](https://t.me/BotFather) on Telegram)

### Setup

```bash
git clone https://github.com/apiguy/kodo.git
cd kodo
bundle install

# Initialize Kodo's home directory
ruby bin/kodo init

# Set your LLM API key (pick any provider)
export ANTHROPIC_API_KEY="sk-ant-..."
# or: export OPENAI_API_KEY="sk-..."
# or: just run Ollama locally — no key needed

# Set up Telegram
export TELEGRAM_BOT_TOKEN="123456:ABC-DEF..."

# Enable Telegram and set your model in the config
# Edit ~/.kodo/config.yml

# Start Kodo
ruby bin/kodo start
```

Now message your bot on Telegram. Kodo is alive.

### CLI Chat (no Telegram needed)

```bash
export ANTHROPIC_API_KEY="sk-ant-..."  # or any provider key
ruby bin/kodo chat
```

## Commands

```
kodo start      Start the Kodo daemon
kodo chat       Chat with Kodo directly in the terminal
kodo memories   List what Kodo remembers about you
kodo status     Show daemon status
kodo init       Create default config in ~/.kodo/
kodo version    Show version
kodo help       Show help
```

## How It Works

Kodo runs a **heartbeat loop** — a periodic cycle that polls your messaging
channels for new messages, processes them through an LLM, and sends responses
back. This heartbeat is what makes Kodo an agent rather than a chatbot: it runs
continuously, can notice things, and will eventually take proactive action on
your behalf.

```
Your Phone (Telegram) ←→ Telegram API ←→ Kodo Daemon ←→ Anthropic Claude
                                              │
                                         Memory Store
                                        (conversations,
                                         audit trail)
```

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full system design, component
details, and roadmap.

## Configuration

Kodo stores its config and data in `~/.kodo/`:

```
~/.kodo/
├── config.yml              # LLM provider and channel settings
├── persona.md              # Agent personality and tone (make Kodo yours)
├── user.md                 # Tell Kodo about yourself
├── pulse.md                # What to notice during idle beats
├── origin.md               # First-run onboarding conversation
└── memory/
    ├── conversations/      # Chat history (per-conversation JSON)
    ├── knowledge/          # Long-term remembered facts (JSONL)
    └── audit/              # Daily audit logs (JSONL)
```

### Prompt Files

Kodo's personality is defined by **plain Markdown files**, not code. Edit
them to make the agent yours:

- **`persona.md`** — How Kodo talks. Tone, style, opinions. "Respond like
  a senior engineer doing code review" is more useful than "be helpful."
- **`user.md`** — Who you are. Name, role, timezone, current projects.
  Helps Kodo give contextual answers.
- **`pulse.md`** — What Kodo should pay attention to during idle heartbeat
  cycles. "Remind me about standup at 9:45am" or "summarize unread messages
  if more than 5 accumulate."
- **`origin.md`** — Runs on first conversation only. Kodo introduces itself
  and helps you set up.

These files are **advisory** — they shape behavior but cannot override Kodo's
hardcoded security invariants (no data exfiltration, no prompt injection
compliance, no impersonation).

Secrets (API keys, bot tokens) are never stored in config files. Instead, config
references environment variable names using the `_env` suffix convention:

```yaml
llm:
  api_key_env: ANTHROPIC_API_KEY  # reads $ANTHROPIC_API_KEY at runtime
```

## Security

Kodo is being built security-first:

- **Encrypted memory** — conversation history and knowledge encrypted at rest
  (AES-256-GCM)
- **Sensitive data redaction** — regex + LLM-assisted detection scrubs secrets
  before writing to disk
- **Audit trail** — every action logged with what triggered it
- **Layered prompt security** — hardcoded invariants cannot be overridden by
  user-editable files

Planned:

- **Capability-based permissions** — skills declare what they need, you grant
  scoped access
- **Sandboxed skill execution** — skills run in isolated processes
- **Signed skills** — cryptographic verification before loading any skill

## License

MIT

## Links

- **Website:** [kodo.bot](https://kodo.bot)
- **Architecture:** [ARCHITECTURE.md](ARCHITECTURE.md)
- **Development Guide:** [CLAUDE.md](CLAUDE.md)
