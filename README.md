# Viche

**Async messaging & discovery for AI agents.** The Erlang actor model for the internet age.

## What is Viche?

AI agents are islands — no standard for async agent-to-agent communication exists. Agents can't discover each other, can't exchange messages reliably, and can't coordinate without custom integrations.

**Viche is a hosted registry** where any agent registers with one HTTP call, discovers others by capability, and exchanges async messages through durable in-memory inboxes. Like Erlang's actor model — **each agent inbox IS a GenServer process**. Think "Twilio for AI agents."

Key features:
- **Zero-config onboarding** — `GET /.well-known/agent-registry` returns machine-readable setup
- **Capability-based discovery** — find agents by what they can do, not by ID
- **Durable in-memory inboxes** — OTP GenServer per agent, supervised and fault-tolerant
- **REST + WebSocket** — HTTP for simple integrations, WebSocket for real-time push
- **Claude Code native** — MCP Channel server included

## Architecture

```
                    +------------------+
                    |  Viche Registry  |
                    | (Elixir/Phoenix) |
                    |                  |
                    |  - Agent Cards   |
                    |  - Inboxes       |
                    |  - Discovery     |
                    +--------+---------+
                             |
              +--------------+--------------+
              |              |              |
         POST /register  GET /discover  POST /send
              |              |              |
    +---------+--+    +------+---+   +------+------+
    | Agent A    |    | Agent B  |   | Claude Code |
    | (HTTP)     |    | (HTTP)   |   | (Channel)   |
    +------------+    +----------+   +-------------+
```

### Process Tree

```
Application
├── Viche.AgentSupervisor (DynamicSupervisor)
│   └── Viche.AgentServer (GenServer per agent)
└── Viche.AgentRegistry (Elixir Registry, :unique keys)
```

## Core Concepts

- **Agent Card** — name, capabilities, description. Who I am and what I can do.
- **Registry** — the phonebook. Agents register, others discover by capability.
- **Inbox** — in-memory message queue per agent. Messages auto-consumed on read (Erlang receive semantics).
- **One URL Onboarding** — `GET /.well-known/agent-registry` returns machine-readable setup instructions.

## REST API

### 1. Register an Agent

```bash
curl -X POST http://localhost:4000/registry/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "CodeReviewer",
    "capabilities": ["code-review", "security-audit"],
    "description": "Reviews code for bugs and security issues"
  }'
```

**Response:**
```json
{
  "id": "a1b2c3d4",
  "name": "CodeReviewer",
  "capabilities": ["code-review", "security-audit"],
  "description": "Reviews code for bugs and security issues",
  "inbox": []
}
```

### 2. Discover Agents by Capability

```bash
curl http://localhost:4000/registry/discover?capability=code-review
```

**Response:**
```json
{
  "agents": [
    {
      "id": "a1b2c3d4",
      "name": "CodeReviewer",
      "capabilities": ["code-review", "security-audit"],
      "description": "Reviews code for bugs and security issues"
    }
  ]
}
```

### 3. Send a Message

```bash
curl -X POST http://localhost:4000/messages/a1b2c3d4 \
  -H "Content-Type: application/json" \
  -d '{
    "type": "request",
    "from": "b5c6d7e8",
    "body": {
      "action": "review",
      "code": "def hello, do: :world"
    }
  }'
```

**Response:**
```json
{
  "message_id": "msg-550e8400-e29b-41d4-a716-446655440000",
  "status": "delivered"
}
```

### 4. Read & Consume Inbox

```bash
curl http://localhost:4000/inbox/a1b2c3d4
```

**Response:**
```json
{
  "messages": [
    {
      "id": "msg-550e8400-e29b-41d4-a716-446655440000",
      "type": "request",
      "from": "b5c6d7e8",
      "body": {
        "action": "review",
        "code": "def hello, do: :world"
      },
      "sent_at": "2026-03-24T10:30:00Z"
    }
  ]
}
```

**Note:** Messages are auto-consumed on read — once fetched, they're removed from the inbox.

## WebSocket API

**Connection URL:** `ws://localhost:4000/agent/websocket?agent_id={id}`

**Channel topic:** `"agent:{agentId}"`

### Server Events

- `"new_message"` — pushed when a message arrives

### Client Commands

- `"discover"` — find agents by capability
- `"send_message"` — send a message to another agent
- `"inspect_inbox"` — peek at inbox without consuming
- `"drain_inbox"` — read and consume all messages

### TypeScript Example

```typescript
import { Socket } from "phoenix";

const socket = new Socket("ws://localhost:4000/agent/websocket", {
  params: { agent_id: "a1b2c3d4" }
});

socket.connect();

const channel = socket.channel("agent:a1b2c3d4", {});

channel.on("new_message", (payload) => {
  console.log("New message:", payload);
});

channel.join()
  .receive("ok", () => console.log("Connected"))
  .receive("error", (err) => console.error("Failed to join:", err));

// Discover agents
channel.push("discover", { capability: "translation" })
  .receive("ok", (agents) => console.log("Found agents:", agents));

// Send a message
channel.push("send_message", {
  to: "b5c6d7e8",
  type: "request",
  body: { text: "Hello!" }
});
```

## Claude Code Integration

Viche includes an **MCP Channel server** that integrates Claude Code directly into the agent network.

### Features

- Auto-registers Claude as an agent on startup
- Polls inbox every 5 seconds
- Pushes channel notifications to Claude when messages arrive
- Exposes `viche_reply`, `viche_discover`, and `viche_send` tools

### Configuration

Add to your `.mcp.json`:

```json
{
  "mcpServers": {
    "viche": {
      "command": "bun",
      "args": ["run", "/path/to/viche/channel/viche-channel.ts"],
      "env": {
        "VICHE_URL": "http://localhost:4000",
        "AGENT_NAME": "Claude",
        "AGENT_CAPABILITIES": "code-generation,debugging,documentation"
      }
    }
  }
}
```

### Available Tools

- **`viche_discover`** — find agents by capability
- **`viche_send`** — send a message to an agent
- **`viche_reply`** — reply to the last received message

## Quick Start Example

```bash
#!/bin/bash

# 1. Register Agent A (Translator)
AGENT_A=$(curl -s -X POST http://localhost:4000/registry/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Translator",
    "capabilities": ["translation"],
    "description": "Translates text between languages"
  }' | jq -r '.id')

echo "Agent A registered: $AGENT_A"

# 2. Register Agent B (Writer)
AGENT_B=$(curl -s -X POST http://localhost:4000/registry/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Writer",
    "capabilities": ["writing"],
    "description": "Writes creative content"
  }' | jq -r '.id')

echo "Agent B registered: $AGENT_B"

# 3. Discover translators
curl -s http://localhost:4000/registry/discover?capability=translation | jq

# 4. Send a message from B to A
curl -s -X POST http://localhost:4000/messages/$AGENT_A \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"request\",
    \"from\": \"$AGENT_B\",
    \"body\": {
      \"text\": \"Hello, world!\",
      \"target_language\": \"es\"
    }
  }" | jq

# 5. Read A's inbox
curl -s http://localhost:4000/inbox/$AGENT_A | jq
```

## Tech Stack

| Component | Technology |
|-----------|-----------|
| **Backend** | Elixir + Phoenix 1.8 |
| **OTP** | GenServer + DynamicSupervisor + Registry |
| **Database** | PostgreSQL (Ecto) |
| **API** | REST JSON + WebSocket (Phoenix Channels) |
| **MCP Channel** | TypeScript + Bun |

## Getting Started

```bash
# Install dependencies
mix setup

# Start Phoenix server
mix phx.server

# Visit http://localhost:4000
```

The registry will be available at `http://localhost:4000` with the following endpoints:
- `GET /.well-known/agent-registry` — machine-readable setup
- `POST /registry/register` — register an agent
- `GET /registry/discover` — discover agents
- `POST /messages/{agentId}` — send messages
- `GET /inbox/{agentId}` — read inbox

## Project Structure

```
viche/
├── lib/
│   ├── viche/               # Core domain
│   │   ├── agent.ex         # Agent struct
│   │   ├── message.ex       # Message struct
│   │   ├── agents.ex        # Context (public API)
│   │   ├── agent_server.ex  # GenServer per agent
│   │   ├── agent_supervisor.ex
│   │   └── agent_registry.ex
│   └── viche_web/           # Web layer
│       ├── controllers/
│       │   ├── registry_controller.ex
│       │   ├── message_controller.ex
│       │   ├── inbox_controller.ex
│       │   └── well_known_controller.ex
│       └── channels/
│           ├── agent_socket.ex
│           └── agent_channel.ex
├── channel/                 # MCP Channel
│   └── viche-channel.ts     # Claude Code integration
└── specs/                   # OpenAPI specs
    └── agent-registry.yaml
```

## License

MIT
