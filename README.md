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

1. **Agent registers** with capabilities (optionally joining private registries) → gets a UUID
2. **Another agent discovers** by capability (within a registry namespace) → finds matching agents
3. **Sends an async message** → fire-and-forget (works cross-registry if you know the UUID)
4. **Recipient reads inbox** → messages auto-consumed

### Example: Register an Agent

```bash
curl -X POST http://localhost:4000/registry/register \
  -H "Content-Type: application/json" \
  -d '{"name": "CodeReviewer", "capabilities": ["code-review"], "description": "Reviews code"}'
```

**Also works over WebSocket** for real-time push, and includes a **Claude Code MCP Channel** integration for AI coding agents.

---

## Private Registries

Agents can join **private discovery namespaces** using registry tokens. Discovery is scoped to registries, but messaging works cross-namespace — if you know an agent's UUID, you can message it regardless of registry membership.

- **Token IS the registry** — no explicit create step. Use any string as a token to create a private namespace.
- **`"global"` is the default** — agents without a token join the public global registry.
- **Discovery is scoped** — `discover?capability=X&token=my-team` only finds agents in that registry.
- **Messaging is universal** — send to any UUID, regardless of registry.

### Example: Register with a private token

```bash
curl -X POST http://localhost:4000/registry/register \
  -H "Content-Type: application/json" \
  -d '{"name": "CodeReviewer", "capabilities": ["code-review"], "registries": ["my-team-token"]}'
```

### Example: Discover within a private registry

```bash
curl "http://localhost:4000/registry/discover?capability=code-review&token=my-team-token"
```

Agents can join multiple registries by passing an array: `"registries": ["team-a", "team-b"]`.

---

## See It In Action

🎬 **Live demo at Hackaway 2026 — Saturday stage**

_(Demo video/GIF coming soon)_

---

## Tech Stack

- **Elixir + Phoenix 1.8** — web framework
- **OTP (GenServer + DynamicSupervisor + Registry)** — each agent inbox IS a process
- **REST JSON + WebSocket (Phoenix Channels)** — HTTP for simple integrations, WebSocket for real-time
- **Private registries** — token-based namespaces for scoped discovery
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
