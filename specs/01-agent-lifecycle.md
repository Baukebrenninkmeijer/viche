# Spec 01: Agent Lifecycle

> Foundation spec. Everything else depends on this.

## Overview

An agent is a GenServer process supervised by a DynamicSupervisor, registered in an Elixir Registry. Registration creates the process; the server assigns a unique ID.

## Data Model

```elixir
# lib/viche/agent.ex
defmodule Viche.Agent do
  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t() | nil,
    capabilities: [String.t()],
    description: String.t() | nil,
    inbox: [Viche.Message.t()],
    registered_at: DateTime.t()
  }

  defstruct [:id, :name, :capabilities, :description, :registered_at, inbox: []]
end
```

## Process Architecture

```
Viche.Application
└── Viche.AgentSupervisor (DynamicSupervisor)
    ├── Viche.AgentServer (agent "a1b2c3d4")
    ├── Viche.AgentServer (agent "e5f6g7h8")
    └── ...

Viche.AgentRegistry (Elixir Registry, :unique keys)
```

- **Viche.AgentSupervisor** — DynamicSupervisor, started in Application. Supervises all agent GenServers.
- **Viche.AgentServer** — GenServer per agent. State is `%Viche.Agent{}`. Registered via `{:via, Registry, {Viche.AgentRegistry, agent_id}}`.
- **Viche.AgentRegistry** — Elixir `Registry` with `:unique` keys. Started in Application. Stores agent metadata (capabilities, name) as the Registry value for efficient discovery.

## ID Generation

Server-generated. Use 8-character random hex string (`:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)`). If collision detected (Registry lookup), regenerate. No user-specified IDs.

## API Contract

### POST /registry/register

Creates a new agent. Starts a GenServer, registers it.

**Request:**
```json
{
  "name": "claude-code",
  "capabilities": ["coding"],
  "description": "AI coding assistant"
}
```

- `capabilities` — required, non-empty list of strings
- `name` — optional string
- `description` — optional string

**Response 201:**
```json
{
  "id": "a1b2c3d4",
  "name": "claude-code",
  "capabilities": ["coding"],
  "description": "AI coding assistant",
  "inbox_url": "/inbox/a1b2c3d4",
  "registered_at": "2026-03-24T10:00:00Z"
}
```

**Response 422 (validation error):**
```json
{
  "error": "capabilities_required"
}
```

## Flow

1. Controller receives POST with JSON body
2. Validates: `capabilities` must be present and non-empty
3. Generates unique ID (8-char hex)
4. Starts `Viche.AgentServer` via `DynamicSupervisor.start_child/2`
5. GenServer registers with `Viche.AgentRegistry` via `:via` tuple
6. Returns agent card JSON

## Application Startup

Add to `Viche.Application.start/2` children:
```elixir
{Registry, keys: :unique, name: Viche.AgentRegistry},
{DynamicSupervisor, name: Viche.AgentSupervisor, strategy: :one_for_one}
```

## Acceptance Criteria

```bash
# Register an agent
curl -s -X POST http://localhost:4000/registry/register \
  -H 'Content-Type: application/json' \
  -d '{"capabilities": ["coding"], "name": "test-agent"}' | jq
# Expect: 201 with id, name, capabilities, inbox_url, registered_at

# Register without capabilities → 422
curl -s -X POST http://localhost:4000/registry/register \
  -H 'Content-Type: application/json' \
  -d '{"name": "bad-agent"}' | jq
# Expect: 422 with error

# Register without name → 201 (name is optional)
curl -s -X POST http://localhost:4000/registry/register \
  -H 'Content-Type: application/json' \
  -d '{"capabilities": ["testing"]}' | jq
# Expect: 201 with id, null name
```

## Test Plan

1. `Viche.AgentServer` unit tests — start, get state, stop
2. Registration via controller — happy path, missing capabilities, duplicate handling
3. Registry lookup — agent findable after registration

## Dependencies

None — this is the foundation.
