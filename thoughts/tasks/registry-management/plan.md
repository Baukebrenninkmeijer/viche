# Dynamic Registry Join/Leave

## TL;DR

> **Summary**: Add `join_registry/2` and `leave_registry/2` to Viche so agents can dynamically manage registry membership after initial registration — exposed via domain API, HTTP REST, WebSocket channel events, and all three plugin clients (OpenClaw, OpenCode, MCP/Claude Code).
> **Deliverables**: Domain functions, HTTP endpoints, channel events, OpenClaw + OpenCode + MCP tools, full TDD test coverage
> **Effort**: Medium (2–3 days)
> **Parallel Execution**: NO — sequential (each phase depends on prior)

---

## Context

### Original Request
User wants agents to interactively manage registries at runtime. Currently registries are only set during registration. The user started by looking at `channel/openclaw-plugin-viche/tools.ts` and noticing it lacks register/deregister functions for registry management.

### Research Findings (Wave 1)
| Source | Finding | Implication |
|--------|---------|-------------|
| `lib/viche/agent_server.ex:50-67` | Registry metadata set at `start_link` via `{:via, Registry, {name, key, meta}}` | Must use `Registry.update_value/3` from owning process to update |
| `lib/viche/agent_server.ex:99-131` | State shape: `{%Agent{registries: [...]}, %{grace_timer_ref: ref}}` | Both Agent struct AND Registry ETS metadata must stay in sync |
| `lib/viche/agents.ex:495-514` | `broadcast_agent_joined/1` iterates ALL registries; `broadcast_agent_left/2` same | Dynamic join/leave needs SCOPED broadcast helpers (single token) |
| `lib/viche_web/channels/agent_channel.ex:56-66` | `join("registry:" <> token)` checks `token in (meta.registries)` from Registry ETS | After `Registry.update_value/3`, new token is immediately visible for channel join |
| `lib/viche/agents.ex:329-340` | `valid_token?/1`: 4-256 chars, `^[a-zA-Z0-9._-]+$` | Reuse for join validation |
| `channel/openclaw-plugin-viche/tools.ts:85-306` | 3 tools via factory pattern, HTTP REST calls, TypeBox schemas | Follow same pattern for new tools |
| Oracle review | `Registry.update_value/3` must be called from owning process | Join/leave logic goes through AgentServer handle_call |
| Oracle review | Disallow leaving last registry (not hard-protect "global") | Invariant: agent always belongs to ≥1 registry |

### Interview Decisions
- **Idempotency**: Strict errors (`:already_in_registry`, `:not_in_registry`) — not silent idempotent
- **Last registry policy**: Cannot leave last registry (`:cannot_leave_last_registry`) — "global" is NOT special-cased
- **Token normalization**: Preserve case (current behavior) — no forced lowercase
- **Channel eviction on leave**: NOT in scope — join-time-only auth (document as known limitation)

### Defaults (proceeding unless you object)
- Following existing `handle_call` pattern from `agent_server.ex:133-163`
- Following existing HTTP controller pattern from `registry_controller.ex`
- Following existing channel `handle_in` pattern from `agent_channel.ex:83-177`
- Following existing tool factory pattern from `openclaw-plugin-viche/tools.ts:85-306`
- TDD approach with tests in existing test files
- No schema/migration changes (all in-memory)

---

## Objectives

### Core Objective
Enable agents to dynamically join and leave registries after initial registration, maintaining consistency between GenServer state and Registry ETS metadata, with proper broadcasts and error handling.

### Scope
| IN (Must Ship) | OUT (Explicit Exclusions) |
|----------------|---------------------------|
| `Viche.Agents.join_registry/2` and `leave_registry/2` | UI changes for registry management |
| `AgentServer` handle_call clauses for join/leave | Auth/permissions per registry |
| HTTP POST endpoints for join/leave | Channel eviction on leave |
| WebSocket channel events for join/leave | Token normalization (lowercase) |
| OpenClaw plugin `viche_join_registry` and `viche_leave_registry` tools | Bulk join/leave operations |
| OpenCode plugin `viche_join_registry` and `viche_leave_registry` tools | |
| MCP channel (viche-channel.ts) `viche_join_registry` and `viche_leave_registry` tools | |
| Scoped broadcasts (`agent_joined`/`agent_left` per token) | |
| Error cases: agent_not_found, invalid_token, already_in_registry, not_in_registry, cannot_leave_last_registry | |

### Definition of Done
- [ ] `Viche.Agents.join_registry(agent_id, token)` works with all error cases
- [ ] `Viche.Agents.leave_registry(agent_id, token)` works with all error cases
- [ ] HTTP endpoints return correct status codes for all cases
- [ ] WebSocket channel events work for join/leave
- [ ] OpenClaw plugin exposes `viche_join_registry` and `viche_leave_registry` tools
- [ ] OpenCode plugin exposes `viche_join_registry` and `viche_leave_registry` tools
- [ ] MCP channel exposes `viche_join_registry` and `viche_leave_registry` tools
- [ ] Broadcasts fire on dynamic join/leave to affected registry topic only
- [ ] After dynamic join, agent can join `registry:{token}` channel
- [ ] After dynamic join, agent appears in discovery for that registry
- [ ] All tests pass: `mix test`
- [ ] All quality gates pass: `mix precommit`

### Must NOT Have (Guardrails)
- No direct calls to `AgentServer` from web layer — always through `Viche.Agents`
- No `Process.sleep/1` in tests — use `Process.monitor/1` or `:sys.get_state/1`
- No hardcoded special treatment of `"global"` registry
- No channel eviction logic (out of scope)
- No modifications to existing registration flow

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: YES — `test/viche/agents_test.exs`, `test/viche/agent_server_test.exs`, `test/viche_web/channels/agent_channel_test.exs`, `test/viche_web/controllers/registry_controller_test.exs`
- **Approach**: TDD (RED → GREEN → VALIDATE)
- **Framework**: ExUnit with `start_supervised!/1` for process management

### If TDD
Each phase follows RED-GREEN-REFACTOR aligned with Vulkanus workflow.

---

## Execution Phases

### Dependency Graph
```
Phase 1 (domain: AgentServer + Agents context)
    ↓
Phase 2 (HTTP: RegistryController endpoints)
    ↓
Phase 3 (WebSocket: AgentChannel events)
    ↓
Phase 4 (Plugin: openclaw-plugin-viche tools)     ← uses HTTP (Phase 2)
Phase 5 (Plugin: opencode-plugin-viche tools)     ← uses HTTP (Phase 2)
Phase 6 (Plugin: viche-channel.ts MCP tools)      ← uses WebSocket (Phase 3)
```
Note: Phases 4, 5, 6 can run in parallel — they all depend on Phases 1-3 but not on each other.

---

### Phase 1: Domain Layer — `join_registry/2` and `leave_registry/2`

**Goal**: Add atomic join/leave operations to the domain layer with proper state sync, validation, and broadcasts.

**Files** (CONFIRMED by research):
- `lib/viche/agent_server.ex` — Add two `handle_call` clauses: `{:join_registry, token}` and `{:leave_registry, token}`
- `lib/viche/agents.ex` — Add public functions `join_registry/2` and `leave_registry/2`; add scoped broadcast helpers `broadcast_registry_joined/2` and `broadcast_registry_left/2`

**Tests** (`test/viche/agents_test.exs` — new `describe` blocks):

**`join_registry/2` behaviors:**
- Given a registered agent and a valid token NOT in its registries, when `join_registry(agent_id, token)`, then returns `{:ok, %Agent{}}` with token added to registries
- Given a registered agent and a valid token NOT in its registries, when `join_registry(agent_id, token)`, then Registry ETS metadata includes the new token (verify via `Registry.lookup/2`)
- Given a registered agent and a valid token NOT in its registries, when `join_registry(agent_id, token)`, then `agent_joined` broadcast is sent to `registry:{token}` PubSub topic
- Given a registered agent and a token ALREADY in its registries, when `join_registry(agent_id, token)`, then returns `{:error, :already_in_registry}`
- Given a non-existent agent_id, when `join_registry(agent_id, token)`, then returns `{:error, :agent_not_found}`
- Given an invalid token (too short, special chars), when `join_registry(agent_id, token)`, then returns `{:error, :invalid_token}`
- Given a registered agent that joins a new registry, when `discover(%{capability: cap, registry: new_token})`, then the agent appears in results

**`leave_registry/2` behaviors:**
- Given a registered agent with multiple registries and a token IN its registries, when `leave_registry(agent_id, token)`, then returns `{:ok, %Agent{}}` with token removed from registries
- Given a registered agent with multiple registries and a token IN its registries, when `leave_registry(agent_id, token)`, then Registry ETS metadata excludes the removed token
- Given a registered agent with multiple registries and a token IN its registries, when `leave_registry(agent_id, token)`, then `agent_left` broadcast is sent to `registry:{token}` PubSub topic
- Given a registered agent with a token NOT in its registries, when `leave_registry(agent_id, token)`, then returns `{:error, :not_in_registry}`
- Given a registered agent with exactly ONE registry, when `leave_registry(agent_id, token)`, then returns `{:error, :cannot_leave_last_registry}`
- Given a non-existent agent_id, when `leave_registry(agent_id, token)`, then returns `{:error, :agent_not_found}`
- Given an invalid token, when `leave_registry(agent_id, token)`, then returns `{:error, :invalid_token}`
- Given a registered agent that leaves a registry, when `discover(%{capability: cap, registry: left_token})`, then the agent does NOT appear in results

**Commands**:
```bash
mix test test/viche/agents_test.exs --trace
mix precommit
```

**Dependencies**: None (can start immediately)

**Must NOT do**:
- Modify existing `register_agent/1` flow
- Call `Registry.update_value/3` from outside the GenServer process
- Add any web layer code

**Pattern Reference**: Follow `lib/viche/agent_server.ex:133-163` for handle_call pattern; follow `lib/viche/agents.ex:150-159` for context function pattern with `with` pipeline validation

**Implementation Notes**:

1. **AgentServer handle_call `{:join_registry, token}`** (in `agent_server.ex`):
   - Check `token in agent.registries` → if yes, reply `{:error, :already_in_registry}`
   - Update `agent = %{agent | registries: agent.registries ++ [token]}`
   - Call `Registry.update_value(Viche.AgentRegistry, agent.id, fn meta -> %{meta | registries: agent.registries} end)` — this works because we're inside the owning process
   - Reply `{:reply, {:ok, agent}, {agent, meta}}`

2. **AgentServer handle_call `{:leave_registry, token}`** (in `agent_server.ex`):
   - Check `length(agent.registries) <= 1` → if yes, reply `{:error, :cannot_leave_last_registry}`
   - Check `token not in agent.registries` → if yes, reply `{:error, :not_in_registry}`
   - Update `agent = %{agent | registries: List.delete(agent.registries, token)}`
   - Call `Registry.update_value/3` same as above
   - Reply `{:reply, {:ok, agent}, {agent, meta}}`

3. **Agents context `join_registry/2`** (in `agents.ex`):
   ```
   def join_registry(agent_id, token) do
     with true <- valid_token?(token) || {:error, :invalid_token},
          {:ok, agent} <- call_agent(agent_id, {:join_registry, token}) do
       broadcast_registry_joined(agent, token)
       {:ok, agent}
     end
   end
   ```

4. **Agents context `leave_registry/2`** (in `agents.ex`):
   ```
   def leave_registry(agent_id, token) do
     with true <- valid_token?(token) || {:error, :invalid_token},
          {:ok, agent} <- call_agent(agent_id, {:leave_registry, token}) do
       broadcast_registry_left(agent.id, token)
       {:ok, agent}
     end
   end
   ```

5. **Scoped broadcast helpers** (in `agents.ex`):
   - `broadcast_registry_joined(agent, token)` — broadcasts `agent_joined` to `registry:{token}` only
   - `broadcast_registry_left(agent_id, token)` — broadcasts `agent_left` to `registry:{token}` only

6. **Note on `call_agent/2`**: Check if a private helper already exists for GenServer.call with agent lookup. If not, extract one from existing patterns (e.g., `send_message/1` at line 230 does `Registry.lookup` + `AgentServer.receive_message`). The helper should handle `:agent_not_found` consistently.

**TDD Gates**:
- RED: Write all test cases above — they should all fail (functions don't exist)
- GREEN: Implement `AgentServer` handle_call clauses, then `Agents` context functions
- VALIDATE: `mix precommit`

---

### Phase 2: HTTP Layer — REST Endpoints for Join/Leave

**Goal**: Expose join/leave as HTTP POST endpoints following existing controller patterns.

**Files** (CONFIRMED by research):
- `lib/viche_web/controllers/registry_controller.ex` — Add `join/2` and `leave/2` action functions
- `lib/viche_web/router.ex` — Add routes under existing `/registry` scope (lines 43-48)

**Tests** (`test/viche_web/controllers/registry_controller_test.exs` — new `describe` blocks):

**`POST /registry/:agent_id/join` behaviors:**
- Given a registered agent and valid token, when POST with `{"token": "new-team"}`, then returns 200 with `{"registries": ["global", "new-team"]}`
- Given a registered agent and token already in registries, when POST, then returns 409 with `{"error": "already_in_registry"}`
- Given a non-existent agent_id, when POST, then returns 404 with `{"error": "agent_not_found"}`
- Given an invalid token (too short), when POST, then returns 422 with `{"error": "invalid_token"}`
- Given missing `token` field in body, when POST, then returns 422 with `{"error": "missing_token"}`

**`POST /registry/:agent_id/leave` behaviors:**
- Given a registered agent with multiple registries and valid token, when POST with `{"token": "old-team"}`, then returns 200 with `{"registries": ["global"]}`
- Given a registered agent with one registry, when POST, then returns 422 with `{"error": "cannot_leave_last_registry"}`
- Given a token not in agent's registries, when POST, then returns 409 with `{"error": "not_in_registry"}`
- Given a non-existent agent_id, when POST, then returns 404 with `{"error": "agent_not_found"}`
- Given an invalid token, when POST, then returns 422 with `{"error": "invalid_token"}`

**Commands**:
```bash
mix test test/viche_web/controllers/registry_controller_test.exs --trace
mix precommit
```

**Dependencies**: Phase 1 (domain functions must exist)

**Must NOT do**:
- Call `AgentServer` directly — only call `Viche.Agents.join_registry/2` and `leave_registry/2`
- Add any business logic in the controller
- Modify existing register/discover endpoints

**Pattern Reference**: Follow `lib/viche_web/controllers/registry_controller.ex` for controller pattern; follow `lib/viche_web/router.ex:43-48` for route scope

**Implementation Notes**:

1. **Routes** (in `router.ex`, inside existing `/registry` scope at line 43):
   ```elixir
   post "/:agent_id/join", RegistryController, :join
   post "/:agent_id/leave", RegistryController, :leave
   ```

2. **Controller actions** (in `registry_controller.ex`):
   ```elixir
   def join(conn, %{"agent_id" => agent_id, "token" => token}) do
     case Agents.join_registry(agent_id, token) do
       {:ok, agent} -> json(conn, %{registries: agent.registries})
       {:error, :agent_not_found} -> conn |> put_status(404) |> json(%{error: "agent_not_found"})
       {:error, :invalid_token} -> conn |> put_status(422) |> json(%{error: "invalid_token"})
       {:error, :already_in_registry} -> conn |> put_status(409) |> json(%{error: "already_in_registry"})
     end
   end
   ```
   Same pattern for `leave/2` with its error cases.

3. **Missing token param**: Add a fallback clause `def join(conn, %{"agent_id" => _})` that returns 422 with `"missing_token"`.

**Error → HTTP Status Mapping**:
| Domain Error | HTTP Status | Response Body |
|---|---|---|
| `:agent_not_found` | 404 | `{"error": "agent_not_found"}` |
| `:invalid_token` | 422 | `{"error": "invalid_token"}` |
| `:already_in_registry` | 409 | `{"error": "already_in_registry"}` |
| `:not_in_registry` | 409 | `{"error": "not_in_registry"}` |
| `:cannot_leave_last_registry` | 422 | `{"error": "cannot_leave_last_registry"}` |

**TDD Gates**:
- RED: Write all controller test cases — they should fail (routes/actions don't exist)
- GREEN: Add routes and controller actions
- VALIDATE: `mix precommit`

---

### Phase 3: WebSocket Layer — Channel Events for Join/Leave

**Goal**: Add `"join_registry"` and `"leave_registry"` handle_in clauses to AgentChannel so WebSocket-connected agents can manage registries in real-time.

**Files** (CONFIRMED by research):
- `lib/viche_web/channels/agent_channel.ex` — Add two `handle_in/3` clauses

**Tests** (`test/viche_web/channels/agent_channel_test.exs` — new `describe` blocks):

**`"join_registry"` event behaviors:**
- Given a connected agent on `agent:{id}` channel, when push `"join_registry"` with `%{"token" => "new-team"}`, then reply is `{:ok, %{"registries" => [...]}}` with new token included
- Given a connected agent, when push `"join_registry"` with token already in registries, then reply is `{:error, %{"error" => "already_in_registry"}}`
- Given a connected agent, when push `"join_registry"` with invalid token, then reply is `{:error, %{"error" => "invalid_token"}}`
- Given a connected agent, when push `"join_registry"` without `"token"` key, then reply is `{:error, %{"error" => "missing_field", "field" => "token"}}`

**`"leave_registry"` event behaviors:**
- Given a connected agent with multiple registries on `agent:{id}` channel, when push `"leave_registry"` with `%{"token" => "old-team"}`, then reply is `{:ok, %{"registries" => [...]}}` with token removed
- Given a connected agent with one registry, when push `"leave_registry"`, then reply is `{:error, %{"error" => "cannot_leave_last_registry"}}`
- Given a connected agent, when push `"leave_registry"` with token not in registries, then reply is `{:error, %{"error" => "not_in_registry"}}`
- Given a connected agent, when push `"leave_registry"` with invalid token, then reply is `{:error, %{"error" => "invalid_token"}}`

**Commands**:
```bash
mix test test/viche_web/channels/agent_channel_test.exs --trace
mix precommit
```

**Dependencies**: Phase 1 (domain functions must exist)

**Must NOT do**:
- Call `AgentServer` directly — only call `Viche.Agents` context functions
- Add business logic in the channel handler
- Modify existing channel events

**Pattern Reference**: Follow `lib/viche_web/channels/agent_channel.ex:83-177` for handle_in pattern (especially the `"discover"` handler with error mapping)

**Implementation Notes**:

1. **handle_in `"join_registry"`** (in `agent_channel.ex`):
   ```elixir
   def handle_in("join_registry", %{"token" => token}, socket) do
     agent_id = socket.assigns.agent_id

     case Agents.join_registry(agent_id, token) do
       {:ok, agent} ->
         {:reply, {:ok, %{registries: agent.registries}}, socket}
       {:error, reason} ->
         {:reply, {:error, %{error: to_string(reason)}}, socket}
     end
   end

   def handle_in("join_registry", _params, socket) do
     {:reply, {:error, %{error: "missing_field", field: "token"}}, socket}
   end
   ```

2. **handle_in `"leave_registry"`**: Same pattern as above with `Agents.leave_registry/2`.

3. **Placement**: Insert BEFORE the catch-all `handle_in(_event, _params, socket)` at line 177.

**TDD Gates**:
- RED: Write all channel test cases — they should fail (events not handled)
- GREEN: Add handle_in clauses
- VALIDATE: `mix precommit`

---

### Phase 4: Plugin Layer — OpenClaw Tools for Join/Leave

**Goal**: Add `viche_join_registry` and `viche_leave_registry` tools to the OpenClaw plugin, following the existing tool factory pattern.

**Files** (CONFIRMED by research):
- `channel/openclaw-plugin-viche/tools.ts` — Add two new tool registrations in `registerVicheTools` function (after line 306)

**Tests**: Manual verification (TypeScript plugin tests are not in the existing test infrastructure)
- Verify tool registration by checking OpenClaw tool list
- Verify join: call `viche_join_registry` with a valid token → expect success message with updated registries
- Verify leave: call `viche_leave_registry` with a valid token → expect success message with updated registries
- Verify error: call `viche_join_registry` when not connected → expect "Not connected" error

**Commands**:
```bash
# Start Phoenix server
iex -S mix phx.server

# In another terminal, start OpenClaw with plugin
# Then use viche_join_registry / viche_leave_registry tools
```

**Dependencies**: Phase 2 (HTTP endpoints must exist — tools use REST)

**Must NOT do**:
- Use WebSocket channel for join/leave (tools use HTTP REST, consistent with existing tools)
- Modify existing tools
- Change the `requireConnected` contract

**Pattern Reference**: Follow `channel/openclaw-plugin-viche/tools.ts:161-242` (viche_send tool) for tool structure with `requireConnected` guard

**Implementation Notes**:

1. **Tool: `viche_join_registry`** (in `tools.ts`):
   - **Parameters**: `token: Type.String({ description: "Registry token to join", minLength: 4, maxLength: 256, pattern: "^[a-zA-Z0-9._-]+$" })`
   - **Execute**:
     1. `requireConnected(state)` guard
     2. `POST ${registryUrl}/registry/${encodeURIComponent(state.agentId)}/join` with body `{ token }`
     3. Map HTTP status to user-friendly messages:
        - 200 → `"Joined registry '{token}'. Current registries: [...]"`
        - 404 → `"Agent not found..."`
        - 409 → `"Already in registry '{token}'"`
        - 422 → `"Invalid token: ..."`
     4. Return `textResult(message)`

2. **Tool: `viche_leave_registry`** (in `tools.ts`):
   - **Parameters**: `token: Type.String({ ... })` — same schema as join
   - **Execute**: Same pattern as join but `POST .../leave` with appropriate error messages:
     - 200 → `"Left registry '{token}'. Current registries: [...]"`
     - 409 → `"Not in registry '{token}'"`
     - 422 → `"Cannot leave last registry"` or `"Invalid token: ..."`

3. **Registration**: Add `api.registerTool(...)` calls inside `registerVicheTools` function, after the existing 3 tools.

4. **Response type**: Add `JoinLeaveResponse` type to `types.ts`:
   ```typescript
   interface JoinLeaveResponse {
     registries: string[];
   }
   ```

**TDD Gates**:
- RED: N/A (no automated TypeScript tests in project)
- GREEN: Implement tools following existing patterns
- VALIDATE: Manual testing with running Phoenix server + OpenClaw

---

### Phase 5: Plugin Layer — OpenCode Tools for Join/Leave

**Goal**: Add `viche_join_registry` and `viche_leave_registry` tools to the OpenCode plugin, following the existing tool factory pattern with Zod schemas and `ensureSessionReady` guard.

**Files** (CONFIRMED by research):
- `channel/opencode-plugin-viche/tools.ts` — Add two new tool definitions in `createVicheTools` return object (after line 310)
- `channel/opencode-plugin-viche/types.ts` — Add `JoinLeaveResponse` interface (if not already added in Phase 4 types.ts for openclaw)

**Tests**: Manual verification (same as Phase 4)

**Commands**:
```bash
# Start Phoenix server
iex -S mix phx.server

# OpenCode will load plugin automatically
# Then use viche_join_registry / viche_leave_registry tools
```

**Dependencies**: Phase 2 (HTTP endpoints must exist — tools use REST)

**Must NOT do**:
- Use WebSocket channel for join/leave (tools use HTTP REST, consistent with existing tools)
- Modify existing tools
- Change the `ensureSessionReady` contract

**Pattern Reference**: Follow `channel/opencode-plugin-viche/tools.ts:222-265` (viche_send tool) for tool structure with `ensureSessionReady` guard and Zod schemas

**Implementation Notes**:

1. **Tool: `viche_join_registry`** (in `tools.ts`):
   - **Parameters** (Zod): `token: z.string().min(4).max(256).regex(/^[a-zA-Z0-9._-]+$/).describe("Registry token to join (4-256 chars, alphanumeric + . _ -)")`
   - **Execute**:
     1. `ensureSessionReady(context.sessionID)` guard (same as viche_send)
     2. `POST ${registryUrl}/registry/${encodeURIComponent(sessionState.agentId)}/join` with body `{ token }`
     3. On 200: parse response as `JoinLeaveResponse`, return `"Joined registry '{token}'. Current registries: [...]"`
     4. On error: map HTTP status to user-friendly message (same table as Phase 4)
   - **Shape**: follows `ToolDefinition` interface — `{ description, args: z.ZodRawShape, execute(args, context) }`

2. **Tool: `viche_leave_registry`** (in `tools.ts`):
   - **Parameters**: Same Zod schema as join
   - **Execute**: Same pattern as join but `POST .../leave` with appropriate error messages

3. **Return object**: Add to the return statement: `return { viche_discover, viche_send, viche_reply, viche_join_registry, viche_leave_registry };`

4. **Response type**: Add `JoinLeaveResponse` to `types.ts` (if needed):
   ```typescript
   export interface JoinLeaveResponse {
     registries: string[];
   }
   ```

**Key Differences from Phase 4 (OpenClaw)**:
| Aspect | OpenClaw (Phase 4) | OpenCode (Phase 5) |
|--------|-------------------|-------------------|
| Schema library | TypeBox (`Type.String(...)`) | Zod (`z.string()...`) |
| Guard | `requireConnected(state)` | `ensureSessionReady(context.sessionID)` |
| Agent ID source | `state.agentId` | `sessionState.agentId` (from ensureSessionReady) |
| Registration pattern | `api.registerTool((ctx) => tool)` factory | Return `Record<string, ToolDefinition>` from `createVicheTools` |
| Tool context | `OpenClawPluginToolContext` | `{ sessionID: string }` |

**TDD Gates**:
- RED: N/A (no automated TypeScript tests for tools in project)
- GREEN: Implement tools following existing patterns
- VALIDATE: Manual testing with running Phoenix server + OpenCode

---

### Phase 6: Plugin Layer — MCP/Claude Code Tools for Join/Leave

**Goal**: Add `viche_join_registry` and `viche_leave_registry` tools to the Claude Code MCP channel, following the existing tool pattern with JSON Schema literals and WebSocket `channelPush`.

**Files** (CONFIRMED by research):
- `channel/viche-channel.ts` — Add two new tool definitions in `ListToolsRequestSchema` handler (line 215-285) and two new `if (toolName === ...)` blocks in `CallToolRequestSchema` handler (line 288-371)

**Tests**: Manual verification

**Commands**:
```bash
# Start Phoenix server
iex -S mix phx.server

# Launch Claude Code with Viche channel
claude --dangerously-load-development-channels server:viche --dangerously-skip-permissions

# Then use viche_join_registry / viche_leave_registry tools
```

**Dependencies**: Phase 3 (WebSocket channel events must exist — MCP tools use `channelPush`)

**Must NOT do**:
- Use HTTP REST (this plugin uses WebSocket channel push for all operations, unlike OpenClaw/OpenCode)
- Modify existing tools
- Change the MCP server contract

**Pattern Reference**: Follow `channel/viche-channel.ts:302-321` (viche_discover tool) for ListTools schema pattern; follow `channel/viche-channel.ts:323-349` (viche_send tool) for CallTool handler with `channelPush`

**Implementation Notes**:

1. **ListToolsRequestSchema handler** — add two entries to the `tools` array:

   ```typescript
   {
     name: "viche_join_registry",
     description: "Join a registry on the Viche network. Adds your agent to the specified registry for scoped discovery.",
     inputSchema: {
       type: "object" as const,
       properties: {
         token: {
           type: "string",
           description: "Registry token to join (4-256 chars, alphanumeric + . _ -)",
           minLength: 4,
           maxLength: 256,
           pattern: "^[a-zA-Z0-9._-]+$",
         },
       },
       required: ["token"],
     },
   },
   ```
   Same for `viche_leave_registry` with appropriate description.

2. **CallToolRequestSchema handler** — add two blocks:

   ```typescript
   if (toolName === "viche_join_registry") {
     const args = request.params.arguments as { token: string };
     try {
       const resp = await channelPush<{ registries: string[] }>(
         activeChannel,
         "join_registry",
         { token: args.token }
       );
       return {
         content: [{
           type: "text",
           text: `Joined registry '${args.token}'. Current registries: ${resp.registries.join(", ")}`,
         }],
       };
     } catch (err) {
       const message = err instanceof Error ? err.message : String(err);
       return {
         content: [{ type: "text", text: `Failed to join registry: ${message}` }],
       };
     }
   }
   ```
   Same pattern for `viche_leave_registry` with `"leave_registry"` event.

**Key Differences from Phase 4/5**:
| Aspect | OpenClaw/OpenCode (Phase 4/5) | MCP Channel (Phase 6) |
|--------|------------------------------|----------------------|
| Transport | HTTP REST (`fetch`) | WebSocket (`channelPush`) |
| Schema library | TypeBox / Zod | JSON Schema literal |
| Guard | `requireConnected` / `ensureSessionReady` | `!activeChannel` null check |
| Agent ID source | `state.agentId` / `sessionState.agentId` | Implicit (channel is already authenticated) |
| Registration | Tool factory / return object | `ListToolsRequestSchema` + `CallToolRequestSchema` handlers |

**TDD Gates**:
- RED: N/A (no automated TypeScript tests for MCP channel)
- GREEN: Implement tools following existing patterns
- VALIDATE: Manual testing with running Phoenix server + Claude Code

---

## What We're NOT Doing

| Excluded Item | Reason | Future Ticket? |
|---|---|---|
| Channel eviction on leave | Complex (requires tracking channel subscriptions per agent); join-time-only auth is sufficient for now | Yes — if users report confusion |
| Auth/permissions per registry | No auth model exists yet; would require significant design | Yes — when multi-tenant |
| UI for registry management | Dashboard is read-only currently | Yes — when dashboard gets write capabilities |
| Token normalization (lowercase) | Current behavior preserves case; changing would be breaking | No — unless users report issues |
| Bulk join/leave | YAGNI; single operations are sufficient | No |
| Persistent registry membership | All state is in-memory by design | No — unless durability requirements change |

---

## Known Limitations (Document in Code)

1. **Join-time-only channel authorization**: If an agent leaves a registry while connected to its `registry:{token}` channel, the channel subscription remains active until disconnect. The agent will continue receiving broadcasts on that topic. This is acceptable because:
   - Channel reconnection will fail (join check reads updated metadata)
   - The agent won't appear in discovery for that registry
   - No security risk (registries are for organization, not access control)

2. **No automatic channel join on registry join**: When an agent dynamically joins a registry via HTTP or channel event, they don't automatically subscribe to the `registry:{token}` channel. The client must explicitly join the channel topic after the join_registry call succeeds.

---

## Risks and Mitigations

| Risk | Trigger | Mitigation |
|------|---------|------------|
| Registry ETS metadata out of sync with GenServer state | Bug in handle_call implementation | Test both state sources independently (GenServer.call :get_state AND Registry.lookup) |
| Broadcast storm on rapid join/leave | Agent rapidly toggling registries | GenServer serialization naturally rate-limits; no additional mitigation needed |
| Plugin error messages diverge from server | HTTP status codes change | Define error mapping table (Phase 2) and reference it in Phase 4/5/6 |
| `Registry.update_value/3` called from wrong process | Refactor moves logic outside GenServer | Test verifies metadata update; compile-time can't catch this |

---

## Success Criteria

### Verification Commands
```bash
# Run all tests
mix test

# Run specific test files for this feature
mix test test/viche/agents_test.exs test/viche_web/controllers/registry_controller_test.exs test/viche_web/channels/agent_channel_test.exs --trace

# Run full quality gates
mix precommit

# Check TypeScript compilation for all plugins
cd channel/openclaw-plugin-viche && npx tsc --noEmit && cd ../..
cd channel/opencode-plugin-viche && npx tsc --noEmit && cd ../..
```

### Final Checklist
- [ ] All "IN scope" items implemented and tested
- [ ] All "OUT scope" items confirmed absent
- [ ] All 5 error cases handled consistently across domain/HTTP/WS/plugin
- [ ] Broadcasts verified for dynamic join/leave (scoped to affected token only)
- [ ] Discovery works for dynamically-joined registries
- [ ] Channel join works for dynamically-joined registries
- [ ] `mix precommit` passes (compilation, formatting, Credo, tests, Dialyzer)
- [ ] No `Process.sleep` in tests
- [ ] All processes started with `start_supervised!/1` in tests
- [ ] OpenCode plugin tools registered and functional
- [ ] MCP channel tools registered and functional
- [ ] All 5 tools work in all 3 plugins (discover, send, reply, join_registry, leave_registry)
