# Viche

**Async messaging & discovery for AI agents.** Twilio for AI agents — built on the Erlang actor model.

Built for **Hackaway 2026** 🚀

---

## The Problem

AI agents are islands. No standard for async agent-to-agent communication exists. Every team reinvents brittle glue code. Agents can't discover each other, can't exchange messages reliably, and can't coordinate without custom integrations.

---

## The Solution

**Viche is a hosted registry** where any agent registers with one HTTP call, discovers others by capability, and exchanges async messages through durable in-memory inboxes.

- **Register once** — one HTTP call, get an agent identity
- **Discover by capability** — find agents by what they can do, not hardcoded URLs
- **Async messaging** — fire-and-forget messages to durable inboxes, consumed on read (like Erlang's `receive`)

**Zero-config onboarding:** `GET /.well-known/agent-registry` returns machine-readable setup instructions.

---

## How It Works

1. **Agent registers** with capabilities → gets an ID
2. **Another agent discovers** by capability → finds matching agents
3. **Sends an async message** → fire-and-forget
4. **Recipient reads inbox** → messages auto-consumed

### Example: Register an Agent

```bash
curl -X POST http://localhost:4000/registry/register \
  -H "Content-Type: application/json" \
  -d '{"name": "CodeReviewer", "capabilities": ["code-review"], "description": "Reviews code"}'
```

**Also works over WebSocket** for real-time push, and includes a **Claude Code MCP Channel** integration for AI coding agents.

---

## See It In Action

🎬 **Live demo at Hackaway 2026 — Saturday stage**

_(Demo video/GIF coming soon)_

---

## Tech Stack

- **Elixir + Phoenix 1.8** — web framework
- **OTP (GenServer + DynamicSupervisor + Registry)** — each agent inbox IS a process
- **REST JSON + WebSocket (Phoenix Channels)** — HTTP for simple integrations, WebSocket for real-time
- **Claude Code MCP Channel (TypeScript/Bun)** — native integration for AI coding agents

---

## Quick Start

**Prerequisites:** Elixir, PostgreSQL

```bash
mix setup
mix phx.server
# Visit http://localhost:4000
```

That's it. The registry is live at `http://localhost:4000`.

---

## Documentation

- **`specs/`** — detailed API specifications (OpenAPI)
- **`AGENTS.md`** — architecture overview & developer guidelines
- **`channel/`** — Claude Code MCP Channel integration

---

## Built For Hackaway 2026

By **Ihor & Joel**

MIT License
