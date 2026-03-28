---
date: 2026-03-25T12:15:00+01:00
researcher: mnemosyne
git_commit: HEAD
branch: main
repository: viche
topic: "Deep research on Viche architecture for agent-owned private registries"
scope: "Viche core (Elixir), MCP channel (TypeScript), auth patterns, config"
query_type: map
tags: [research, architecture, auth, private-registries, multi-tenancy]
status: complete
confidence: high
sources_scanned:
  files: 45
  thoughts_docs: 3
---

# Research: Viche Architecture for Agent-Owned Private Registries

**Date**: 2026-03-25T12:15:00+01:00
**Commit**: HEAD
**Branch**: main
**Confidence**: High - comprehensive code review of all relevant modules

## Query
Deep research on Viche's current architecture, the MCP channel integration, and any existing auth/registry patterns — to inform planning of "agent-owned private registries."

## Summary
Viche is currently a **flat global registry** with no authentication, namespacing, or ownership concepts. All agents register into a single namespace, discoverable by any other agent. The architecture is built on Elixir OTP (GenServer per agent, DynamicSupervisor, Registry) with Phoenix Channels for WebSocket. The MCP channel integration uses simple HTTP registration with agent_id as the only identity token. No database persistence for agents — everything is in-memory GenServer state.

---

## A. Viche Core (Elixir Side)

### A.1 Agent Struct (`Viche.Agent`)

**Location**: `lib/viche/agent.ex:1-36`

```elixir
@type t :: %__MODULE__{
  id: String.t(),                    # 8-char hex, server-generated
  name: String.t() | nil,            # optional display name
  capabilities: [String.t()],        # required, non-empty list
  description: String.t() | nil,     # optional
  inbox: list(),                     # in-memory message queue
  registered_at: DateTime.t(),
  connection_type: :websocket | :long_poll,
  last_activity: DateTime.t() | nil,
  polling_timeout_ms: pos_integer()  # default 60_000
}
```

**Key Observations**:
- **NO ownership fields** — no `owner_id`, `tenant_id`, `namespace`, `registry_id`, or `created_by`
- **NO auth fields** — no `token`, `secret`, `api_key`, or `session_id`
- Agent ID is the only identity, generated server-side via `:crypto.strong_rand_bytes(4)`
- Inbox is a simple list, not persisted to database

### A.2 Agent Registration Flow

**Entry Point**: `lib/viche_web/controllers/registry_controller.ex:15-48`

```elixir
def register(conn, params) do
  # Validates polling_timeout_ms (>= 5000 if provided)
  # Builds attrs map from params
  # Calls Agents.register_agent(attrs)
  # Returns JSON with id, name, capabilities, inbox_url, registered_at
end
```

**Context Module**: `lib/viche/agents.ex:65-107`

```elixir
def register_agent(%{capabilities: caps} = attrs) do
  # Validates: capabilities non-empty, all strings
  # Validates: name/description are strings if present
  # Generates unique 8-char hex ID
  # Starts AgentServer via DynamicSupervisor
  # Returns {:ok, %Agent{}}
end
```

**Key Observations**:
- **No authentication required** — any HTTP client can register
- **No rate limiting** — unlimited registrations allowed
- **No ownership tracking** — no way to know who registered an agent
- Registration is fire-and-forget — no session, no token returned beyond agent_id

### A.3 Agent Discovery Mechanism

**Location**: `lib/viche/agents.ex:131-157`

```elixir
def discover(%{capability: "*"}), do: {:ok, list_agents()}
def discover(%{name: "*"}), do: {:ok, list_agents()}
def discover(%{capability: cap}), do: {:ok, find_by_capability(cap)}
def discover(%{name: name}), do: {:ok, find_by_name(name)}
```

**Implementation**: Uses `Registry.select/2` with match specs to query all agents, then filters in Elixir.

**Key Observations**:
- **Global discovery** — any agent can discover any other agent
- **No scoping** — wildcard `*` returns ALL agents in the system
- **No access control** — no way to hide agents from discovery
- Spec `specs/02-discovery.md:99` explicitly notes: "When namespaces/multi-tenancy are added, wildcard will be scoped to the caller's namespace."

### A.4 Agent Process Management

**AgentServer**: `lib/viche/agent_server.ex:1-226`

- GenServer per agent, holds `{%Agent{}, %{grace_timer_ref: nil}}` state
- Registered via `{:via, Registry, {Viche.AgentRegistry, agent_id, meta}}`
- Meta stored in Registry: `%{name: name, capabilities: capabilities, description: description}`
- `restart: :temporary` — no automatic restart on crash

**Application Supervision Tree**: `lib/viche/application.ex:10-18`

```elixir
children = [
  {Registry, keys: :unique, name: Viche.AgentRegistry},
  {DynamicSupervisor, name: Viche.AgentSupervisor, strategy: :one_for_one},
  VicheWeb.Endpoint
]
```

**Key Observations**:
- **Single global Registry** — `Viche.AgentRegistry` is the only namespace
- **No partitioning** — all agents in one DynamicSupervisor
- **No persistence** — agent state lost on process crash or node restart

### A.5 Message Routing

**Location**: `lib/viche/agents.ex:173-203`

```elixir
def send_message(%{to: agent_id, from: from, body: body} = attrs) do
  # Validates type (task/result/ping)
  # Looks up agent in Registry
  # Creates Message struct
  # Calls AgentServer.receive_message/2
  # Broadcasts via Phoenix PubSub: "agent:#{agent_id}"
end
```

**Key Observations**:
- **No sender verification** — `from` field is self-reported, not validated
- **No access control** — any agent can message any other agent
- **Dual delivery** — message stored in GenServer inbox AND broadcast via PubSub

### A.6 WebSocket/Channel Auth

**AgentSocket**: `lib/viche_web/channels/agent_socket.ex:17-22`

```elixir
def connect(%{"agent_id" => agent_id}, socket, _connect_info)
    when is_binary(agent_id) and agent_id != "" do
  {:ok, assign(socket, :agent_id, agent_id)}
end

def connect(_params, _socket, _connect_info), do: :error
```

**AgentChannel**: `lib/viche_web/channels/agent_channel.ex:37-47`

```elixir
def join("agent:" <> agent_id, _params, socket) do
  case Registry.lookup(Viche.AgentRegistry, agent_id) do
    [{pid, _meta}] ->
      send(pid, :websocket_connected)
      {:ok, assign(socket, :agent_id, agent_id)}
    [] ->
      {:error, %{reason: "agent_not_found"}}
  end
end
```

**Key Observations**:
- **Agent ID is the only auth** — knowing the ID grants full access
- **No token verification** — no secret, no signature, no expiry
- **No ownership check** — any client with agent_id can join the channel
- **Impersonation possible** — if you know an agent_id, you can connect as that agent

### A.7 Well-Known Endpoint

**Location**: `lib/viche_web/controllers/well_known_controller.ex:1-149`

Exposes `/.well-known/agent-registry` with:
- Protocol version: `viche/0.1`
- Endpoint schemas for register, discover, send_message, read_inbox
- Lifecycle documentation (polling timeout, grace period)
- WebSocket connection instructions

**Key Observations**:
- **Public endpoint** — no auth required
- **Self-documenting** — agents can auto-configure from this
- **No namespace info** — assumes single global registry

### A.8 Database Schema

**Repo**: `lib/viche/repo.ex` — standard Ecto.Repo

**Migrations**: `priv/repo/migrations/` — **EMPTY** (only `.formatter.exs`)

**Key Observations**:
- **No Ecto schemas** — `Agent` and `Message` are pure Elixir structs
- **No database tables** — all state is in-memory GenServer
- **No persistence** — Fly redeploy = all agents and messages lost
- Issue `viche-beads-7m6` tracks: "Persistence: migrate inbox state to Postgres"

### A.9 Router

**Location**: `lib/viche_web/router.ex:1-70`

```elixir
pipeline :api do
  plug :accepts, ["json"]
end

# No auth plugs in any pipeline

scope "/registry", VicheWeb do
  pipe_through :api
  post "/register", RegistryController, :register
  get "/discover", RegistryController, :discover
end

scope "/messages", VicheWeb do
  pipe_through :api
  post "/:agent_id", MessageController, :send_message
end

scope "/inbox", VicheWeb do
  pipe_through :api
  get "/:agent_id", InboxController, :read_inbox
end
```

**Key Observations**:
- **No auth pipeline** — all endpoints are public
- **No custom plugs** — `lib/viche_web/plugs/` directory does not exist
- **No rate limiting** — no throttling on any endpoint

### A.10 Existing Namespace/Scope/Tenant Concepts

**Search Results**: Grep for `namespace|tenant|owner|private|scope` found:
- `specs/02-discovery.md:99` — "When namespaces/multi-tenancy are added..."
- `.beads/issues.jsonl` — Issue `viche-beads-9lu`: "Auth: agent-owned private registries"

**Key Observations**:
- **No existing implementation** — multi-tenancy is planned but not built
- **No foreign keys** — no `owner_id`, `registry_id`, or similar
- **No scoping logic** — all queries are global

---

## B. MCP Channel (channel/ directory)

### B.1 Main Entry Point

**Location**: `channel/viche-channel.ts:1-361`

Standalone MCP server using `@modelcontextprotocol/sdk`. Runs as subprocess of Claude Code.

### B.2 Agent Registration

**Location**: `channel/viche-channel.ts:45-90`

```typescript
async function register(): Promise<string> {
  const body: RegisterBody = { capabilities: CAPABILITIES };
  if (AGENT_NAME) body.name = AGENT_NAME;
  if (DESCRIPTION) body.description = DESCRIPTION;

  const response = await fetch(`${REGISTRY_URL}/registry/register`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  // Returns agent ID
}
```

**Key Observations**:
- **No auth headers** — plain HTTP POST
- **No tokens sent** — only capabilities, name, description
- **Retry logic** — 3 attempts with 2s backoff

### B.3 WebSocket Connection

**Location**: `channel/viche-channel.ts:117-156`

```typescript
function connectWebSocket(agentId: string, server: Server): void {
  const socket = new Socket(wsUrl, { params: { agent_id: agentId } });
  socket.connect();
  const channel = socket.channel(`agent:${agentId}`, {});
  // Join and listen for new_message events
}
```

**Key Observations**:
- **Agent ID is the only credential** — passed as connection param
- **No token/secret** — anyone with agent_id can connect
- **Phoenix Channel protocol** — standard join/push/receive

### B.4 Message Handling

**Tools exposed**: `viche_discover`, `viche_send`, `viche_reply`

All tools use channel push events:
- `discover` → `{ capability: string }`
- `send_message` → `{ to: string, body: string, type: string }`

**Key Observations**:
- **No auth in tool calls** — agent_id implicit from channel
- **Self-reported sender** — `from` field set by channel, not verified

### B.5 Configuration

**Location**: `channel/.mcp.json.example`

```json
{
  "env": {
    "VICHE_REGISTRY_URL": "http://localhost:4000",
    "VICHE_CAPABILITIES": "coding,refactoring,testing",
    "VICHE_AGENT_NAME": "claude-code",
    "VICHE_DESCRIPTION": "Claude Code AI coding assistant"
  }
}
```

**Key Observations**:
- **Single registry URL** — no concept of multiple registries
- **No auth config** — no token, API key, or secret fields
- **No namespace config** — no registry_id or tenant_id

### B.6 OpenClaw Plugin Variant

**Location**: `channel/openclaw-plugin-viche/`

Similar pattern but uses OpenClaw plugin SDK. Same registration flow, same lack of auth.

---

## C. Existing Auth Patterns

### C.1 Phoenix Auth Generators

**NOT FOUND**:
- No `*_auth.ex` files
- No `User` or `Account` schemas
- No session controllers
- No auth plugs

### C.2 API Authentication

**Current State**: None

- `SPEC.md:79` explicitly states: "no auth tokens (public registry for hackathon)"
- Agent ID serves as pseudo-token but is not secret
- No Bearer auth, no API keys, no HMAC signatures

### C.3 Middleware/Plugs

**NOT FOUND**:
- No `lib/viche_web/plugs/` directory
- No custom auth plugs in router
- No rate limiting plugs

---

## D. Config & Environment

### D.1 Environment Variables

**Production** (`config/runtime.exs`):
- `DATABASE_URL` — Postgres connection
- `SECRET_KEY_BASE` — Phoenix signing key
- `PHX_HOST` — hostname
- `PORT` — HTTP port (default 4000)

**No auth-related env vars** — no `API_KEY`, `AUTH_SECRET`, etc.

### D.2 Application Config

**Location**: `config/config.exs`

Standard Phoenix config. No custom auth or multi-tenancy config.

### D.3 Grace Period Config

**Location**: `lib/viche/agent_server.ex:225`

```elixir
defp grace_period_ms, do: Application.get_env(:viche, :grace_period_ms, 5_000)
```

Only configurable timeout. No namespace or tenant config.

---

## Gaps Identified

| Gap | Search Terms Used | Directories Searched |
|-----|-------------------|---------------------|
| No ownership model | "owner", "tenant", "namespace" | `lib/`, `specs/` |
| No auth mechanism | "token", "auth", "secret", "api_key" | `lib/viche_web/`, `channel/` |
| No database persistence for agents | "Ecto.Schema", "migration" | `lib/viche/`, `priv/repo/` |
| No rate limiting | "rate", "throttle", "limit" | `lib/viche_web/` |
| No access control | "permission", "access", "acl" | `lib/`, `specs/` |
| No private registries | "private", "registry" | `lib/`, `specs/`, `channel/` |
| No agent secrets/tokens | "secret", "token", "credential" | `lib/viche/agent.ex` |

---

## Evidence Index

### Code Files
- `lib/viche/agent.ex:1-36` — Agent struct definition
- `lib/viche/agents.ex:1-308` — Context module (public API)
- `lib/viche/agent_server.ex:1-226` — GenServer implementation
- `lib/viche/application.ex:10-18` — Supervision tree
- `lib/viche_web/router.ex:1-70` — Route definitions
- `lib/viche_web/controllers/registry_controller.ex:1-89` — Registration endpoint
- `lib/viche_web/channels/agent_socket.ex:1-26` — WebSocket auth
- `lib/viche_web/channels/agent_channel.ex:1-159` — Channel handlers
- `lib/viche_web/controllers/well_known_controller.ex:1-149` — Discovery endpoint
- `channel/viche-channel.ts:1-361` — MCP channel implementation
- `channel/openclaw-plugin-viche/service.ts:1-225` — OpenClaw plugin

### Documentation
- `SPEC.md:79` — "no auth tokens (public registry for hackathon)"
- `specs/02-discovery.md:99` — "When namespaces/multi-tenancy are added..."
- `.beads/issues.jsonl` — Issue `viche-beads-9lu` (private registries)

---

## Current State Summary

### What Works Today
1. **Agent Registration** — HTTP POST creates GenServer, returns 8-char ID
2. **Agent Discovery** — Query by capability or name, wildcard returns all
3. **Message Routing** — Fire-and-forget to agent inbox + PubSub broadcast
4. **WebSocket Channels** — Real-time message push via Phoenix Channels
5. **Auto-deregistration** — Polling timeout and WebSocket grace period
6. **MCP Integration** — Claude Code and OpenClaw can register and communicate

### What Doesn't Exist
1. **Authentication** — No tokens, no secrets, no verification
2. **Authorization** — No access control, no permissions
3. **Ownership** — No way to know who registered an agent
4. **Namespacing** — Single global registry, no scoping
5. **Persistence** — All state in-memory, lost on restart
6. **Rate Limiting** — No throttling on any endpoint
7. **Private Registries** — No concept of isolated agent groups

---

## Handoff Inputs for Planning

### Scope
- **Systems involved**: Viche.Agent struct, Viche.Agents context, AgentServer, AgentRegistry, Router, WebSocket auth, MCP channel
- **Estimated touch points**: 8-12 files for minimal private registry support

### Entry Points
- `lib/viche/agent.ex` — Add ownership/namespace fields
- `lib/viche/agents.ex` — Add scoped queries
- `lib/viche_web/router.ex` — Add auth pipeline
- `lib/viche_web/channels/agent_socket.ex` — Add token verification
- `channel/viche-channel.ts` — Add auth config and headers

### Constraints Found
1. **No database schema** — Need migrations for any persistence
2. **Agent ID is public** — Cannot be used as secret token
3. **Registry is global** — Need new data structure for namespacing
4. **MCP channel is stateless** — Auth must work with HTTP + WebSocket
5. **Hackathon timeline** — SPEC.md mentions "4 days build"

### Patterns to Consider
1. **Registry-as-resource** — Each private registry gets its own ID and token
2. **Agent-owns-registry** — Creating agent becomes registry owner
3. **Token-based auth** — Bearer token for API, connection param for WebSocket
4. **Scoped discovery** — Agents only see others in same registry

### Open Questions for Planning
1. Can an agent belong to multiple registries?
2. Should the global registry remain as a "public" option?
3. How do agents discover registries they can join?
4. What's the token lifecycle (expiry, rotation)?
5. Should registry creation require human auth (OAuth) or be agent-initiated?

---

## Related Research

- `thoughts/research/2026-03-24-openclaw-viche-integration.md` — OpenClaw plugin architecture
