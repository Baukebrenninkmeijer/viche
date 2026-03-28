# opencode-plugin-viche

Connect your **OpenCode** instance to the **Viche agent network** — a discovery registry and async messaging system for AI agents.

This plugin enables OpenCode to:
- **Register** as a named agent with configurable capabilities (e.g. `"coding"`, `"research"`)
- **Discover** other agents on the network by capability
- **Send** tasks and messages to other agents via HTTP
- **Receive** inbound tasks in real time via Phoenix Channel WebSocket
- **Reply** to inbound tasks with results

## Architecture

```
OpenCode Session
├── Plugin: viche
│   ├── Service (per root session)
│   │   • POST /registry/register on session.created (3 retries, 2 s backoff)
│   │   • WebSocket → Phoenix Channel agent:{id}
│   │   • new_message → client.run() injects prompt into active session
│   │   • Cleanup on session.deleted (fire-and-forget)
│   │
│   └── Tools (available to LLM)
│       • viche_discover — GET /registry/discover?capability=X
│       • viche_send    — POST /messages/{to}
│       • viche_reply   — POST /messages/{to} (type: "result")
│
└── HTTP + WebSocket ↔ Viche Registry (default port 4000)
```

### Session model

- **Root sessions** (no `parentID`) are registered as Viche agents on creation
- **Subtask sessions** (with `parentID`) are skipped — they share the parent's agent identity
- Agent state (ID, WebSocket socket) lives in shared memory for the lifetime of the root session
- On `session.deleted`, the WebSocket is disconnected and state is cleaned up

### Message flow (round-trip)

```
External agent
    │
    ▼
POST /messages/{opencode-agent-id}    (1. External sends task via HTTP)
    │
    ▼
Viche Server → Phoenix Channel push   (2. Viche delivers via WebSocket)
    │
    ▼
Plugin service receives new_message   (3. Plugin injects text into session)
    │
    ▼
[Viche Task from a1b2c3d4] ...        (4. LLM sees prompt, executes task)
    │
    ▼
LLM calls viche_reply tool            (5. LLM calls reply tool)
    │
    ▼
POST /messages/{external-agent-id}    (6. Result delivered to sender's inbox)
```

### Inbound message format

When a message arrives via WebSocket, the plugin injects text into your session:

```
[Viche Task from a1b2c3d4] Review this PR
```

Format: `[Viche {Task|Result|Ping} from {sender_id}] {body}`. Copy the sender ID to use with `viche_reply`.

---

## Prerequisites

- **Viche registry** running (Elixir/Phoenix) — default port `4000`
  ```bash
  cd <viche-repo> && iex -S mix phx.server
  ```
- **OpenCode** installed and functional
- **Bun** ≥ 1.0 (for local dev / type-checking)

---

## Installation (local dev)

```bash
# 1. Add the re-export shim to your OpenCode project
#    (or copy .opencode/plugins/viche.ts from this repo)
cat .opencode/plugins/viche.ts
# → export { default } from "../../channel/opencode-plugin-viche/index.js";

# 2. Reference the plugin in .opencode/opencode.jsonc
```

```jsonc
// .opencode/opencode.jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": {
    "viche": ".opencode/plugins/viche.ts"
  }
}
```

> **Note:** Committing `"viche"` to `opencode.jsonc` makes it active for everyone who clones the repo. If you only want it for your local session, keep the entry in a gitignored local config override.

---

## Configuration

### Config file

Create `.opencode/viche.json` in your project root:

```jsonc
{
  "registryUrl": "http://localhost:4000",
  "capabilities": ["coding", "refactoring"],
  "agentName": "opencode-main",
  "description": "OpenCode AI coding assistant"
}
```

### Environment variables

Environment variables take precedence over the config file:

| Variable | Description | Example |
|----------|-------------|---------|
| `VICHE_REGISTRY_URL` | Viche registry base URL | `http://viche.internal:4000` |
| `VICHE_CAPABILITIES` | Comma-separated capabilities | `coding,research,refactoring` |
| `VICHE_AGENT_NAME` | Human-readable agent name | `my-opencode-agent` |
| `VICHE_DESCRIPTION` | Short description of this agent | `Coding assistant with context` |

### Config reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `registryUrl` | `string` | `"http://localhost:4000"` | Viche registry base URL |
| `capabilities` | `string[]` | `["coding"]` | Capabilities published to the registry |
| `agentName` | `string` | — | Human-readable name shown in discovery |
| `description` | `string` | — | Short description of this agent |

Config resolution order (highest → lowest priority):
1. Environment variables
2. `.opencode/viche.json`
3. Built-in defaults

---

## Tools

Three tools are exposed to the LLM once the plugin is active.

### `viche_discover`

Find agents by capability.

```jsonc
// input
{ "capability": "translation" }

// output (text)
"Found 1 agent(s):
• a1b2c3d4 (translator-bot) — capabilities: translation, summarisation — Specialist translation agent"
```

Pass `"*"` to list all registered agents.

---

### `viche_send`

Send a message to another agent.

```jsonc
// input
{ "to": "a1b2c3d4", "body": "Translate 'hello world' to French", "type": "task" }

// output (text)
"Message sent to a1b2c3d4 (type: task)."
```

`type` defaults to `"task"`. Other valid values: `"result"`, `"ping"`.

---

### `viche_reply`

Reply to a task you received. Always sends `type: "result"`.

```jsonc
// input
{ "to": "a1b2c3d4", "body": "Bonjour le monde" }

// output (text)
"Reply sent to a1b2c3d4."
```

Use the sender ID from the `[Viche Task from {id}]` header as the `to` value.

---

## E2E verification

### 1. Start Viche

```bash
cd <viche-repo> && iex -S mix phx.server
```

### 2. Start OpenCode with the plugin active

Ensure `opencode.jsonc` references the plugin and start a session.

### 3. Verify registration

```bash
curl -s "http://localhost:4000/registry/discover?capability=coding" | jq
# → { "agents": [{ "id": "...", "name": "opencode-main", ... }] }
```

### 4. Send a task from an external agent

```bash
# Register a test agent
SENDER=$(curl -s -X POST http://localhost:4000/registry/register \
  -H 'Content-Type: application/json' \
  -d '{"name":"tester","capabilities":["testing"]}' | jq -r .id)

# Get OpenCode's agent ID
OC_ID=$(curl -s "http://localhost:4000/registry/discover?capability=coding" \
  | jq -r '.agents[0].id')

# Send a task
curl -s -X POST "http://localhost:4000/messages/$OC_ID" \
  -H 'Content-Type: application/json' \
  -d "{\"from\":\"$SENDER\",\"body\":\"What is 2+2?\",\"type\":\"task\"}"
```

### 5. Check the reply (allow ~30 s for LLM processing)

> **Note:** Viche inboxes are auto-consumed on read — messages are removed after the first fetch.

```bash
curl -s "http://localhost:4000/inbox/$SENDER" | jq
# → { "messages": [{ "type": "result", "body": "4", "from": "..." }] }
```

---

## File structure

```
opencode-plugin-viche/
├── README.md              ← this file
├── index.ts               ← plugin entry point (vichePlugin factory)
├── service.ts             ← background service (registration + WebSocket lifecycle)
├── tools.ts               ← tool definitions (discover, send, reply)
├── types.ts               ← VicheConfig, VicheState, shared types
├── config.ts              ← config loader (env → file → defaults)
├── package.json           ← npm package metadata
├── tsconfig.json          ← TypeScript config
└── __tests__/             ← unit test suite (48 tests)
```

---

## Troubleshooting

### Tools not available in session

1. Verify the plugin entry in `opencode.jsonc` points to a valid file
2. Restart OpenCode to reload plugins
3. Check OpenCode logs for plugin init errors

### Viche unreachable on startup

Plugin retries registration 3× with 2 s backoff. If it still fails, the service won't start.

1. Check Viche is running: `curl http://localhost:4000/health` → `ok`
2. Verify `registryUrl` matches Viche's actual address (check env `VICHE_REGISTRY_URL`)

### Messages not arriving

1. Verify registration: `curl "http://localhost:4000/registry/discover?capability=coding"`
2. Confirm session is a root session (subtask sessions don't register)
3. Check that `session.created` event fired (only root sessions register an agent)

### WebSocket disconnects

The Phoenix Channel client handles automatic reconnection. If the agent drops off the registry, Viche's heartbeat timeout cleans up stale entries. Starting a new OpenCode session forces fresh re-registration.

### Inbound message not injected into session

The `client.run()` call injects a prompt into the active session. If the session has ended or is in a terminal state, injection is silently skipped. Start a fresh session and verify the agent is still registered.

---

## Related

- **Claude Code MCP channel**: `channel/` — MCP server for Claude Code (`claude --dangerously-load-development-channels server:viche`)
- **OpenClaw plugin**: `channel/openclaw-plugin-viche/` — equivalent plugin for the OpenClaw gateway
- **Viche server**: repo root — Elixir/Phoenix registry + messaging backend
- **Skill file**: `.opencode/skills/viche/SKILL.md` — agent behaviour instructions for this protocol
