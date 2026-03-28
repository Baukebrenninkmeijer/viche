# Wildcard Discovery for Viche Agent Registry

## TL;DR

> **Summary**: Add wildcard `"*"` support to agent discovery so clients can retrieve ALL registered agents by passing `capability: "*"` or `name: "*"`.
> **Deliverables**: Updated context module, channel handler, well-known descriptor, and both TypeScript clients
> **Effort**: Short (1-2h)
> **Parallel Execution**: YES — Phases 1-2 can run together, Phase 4-5 are independent of Phase 3

---

## Context

### Original Request
> "implement wildcard discovery for agents. Right now agents only can search by capabilities or names. Let's add a wildcard * which will allow agents to find all!"

### Research Findings
| Source | Finding | Implication |
|--------|---------|-------------|
| `lib/viche/agents.ex:124-133` | `discover/1` has 3 clauses: capability, name, catch-all | Add wildcard clauses BEFORE existing ones (pattern match order matters) |
| `lib/viche/agents.ex:38-42` | `list_agents/0` already returns all agents as `[agent_info()]` | Wildcard can simply delegate to `list_agents/0` — zero new logic |
| `lib/viche_web/controllers/registry_controller.ex:51-66` | Controller calls `Agents.discover/1` via `build_discover_query/1` | No controller changes needed — `"*"` flows through as a normal string |
| `lib/viche_web/channels/agent_channel.ex:59-66` | Channel `handle_in("discover", ...)` pattern-matches on `"capability"` and `"name"` keys | Existing clauses already pass `"*"` to `Agents.discover/1` — no channel changes needed for basic flow |
| `lib/viche_web/controllers/well_known_controller.ex:36-43` | Static `@descriptor` map documents discover endpoint | Must update descriptions to mention wildcard |
| `channel/viche-channel.ts:199-214` | `viche_discover` tool requires `capability` param | Must update description to mention `"*"` wildcard |
| `channel/openclaw-plugin-viche/tools.ts:84-95` | `viche_discover` tool requires `capability` param | Must update description to mention `"*"` wildcard |

### Design Decisions
- When `capability` is `"*"` or `name` is `"*"`, return ALL agents via `list_agents/0`
- New `discover/1` clauses are added ABOVE existing ones (Elixir matches top-down)
- HTTP controller needs NO changes — `build_discover_query/1` already passes `"*"` as a string
- WebSocket channel needs NO code changes — existing `handle_in` clauses already pass `"*"` through
- TypeScript clients: update tool descriptions only (no logic changes needed)

---

## Objectives

### Core Objective
Allow agents to discover ALL registered agents by passing the wildcard string `"*"` as a capability or name query parameter.

### Scope
| IN (Must Ship) | OUT (Explicit Exclusions) |
|----------------|---------------------------|
| `Viche.Agents.discover(%{capability: "*"})` returns all agents | Glob/regex patterns (e.g. `"code*"`) |
| `Viche.Agents.discover(%{name: "*"})` returns all agents | Pagination for large agent lists |
| Well-known descriptor documents wildcard behavior | Rate limiting on wildcard queries |
| Both TS clients mention wildcard in tool descriptions | New API endpoints |
| Tests for all wildcard paths | Changes to `list_agents/0` behavior |

### Definition of Done
- [ ] `mix test test/viche/agents_test.exs` passes with wildcard tests
- [ ] `mix test test/viche_web/controllers/registry_controller_test.exs` passes with wildcard tests
- [ ] `mix test test/viche_web/channels/agent_channel_test.exs` passes with wildcard tests
- [ ] `mix test test/viche_web/controllers/well_known_controller_test.exs` passes with wildcard tests
- [ ] `mix precommit` passes (compilation, formatting, Credo, tests, Dialyzer)
- [ ] TypeScript client descriptions updated

### Must NOT Have (Guardrails)
- No glob/regex pattern matching — only exact `"*"` string
- No new API endpoints or query parameters
- No changes to `list_agents/0` or `format_agent/1`
- No changes to the discover response shape (still `{:ok, [agent_info()]}`)
- No breaking changes to existing discover behavior

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: YES — ExUnit tests for all 4 Elixir modules
- **Approach**: TDD (RED → GREEN → VALIDATE)
- **Framework**: ExUnit with `VicheWeb.ConnCase` and `VicheWeb.ChannelCase`

### TDD Flow
Each phase: write failing test → implement minimal code → run `mix precommit`

---

## Execution Phases

### Dependency Graph
```
Phase 1 (no deps) ──> Phase 2 (needs Phase 1 context changes)
                  ──> Phase 3 (needs Phase 1 context changes)
Phase 1 ────────────> Phase 4 (independent — docs only)
Phase 1 ────────────> Phase 5 (independent — TS clients only)
```

### Phase 1: Add wildcard clauses to `Viche.Agents.discover/1`

**Files** (CONFIRMED):
- `lib/viche/agents.ex` — Add two new `discover/1` function clauses at lines 125-131 (BEFORE existing clauses)
- `test/viche/agents_test.exs` — Add wildcard tests inside existing `describe "discover/1"` block

**Implementation Detail**:
Add two new clauses at the TOP of the `discover/1` function (before line 125):

```elixir
def discover(%{capability: "*"}), do: {:ok, list_agents()}
def discover(%{name: "*"}), do: {:ok, list_agents()}
```

These must appear BEFORE the existing `discover(%{capability: cap})` and `discover(%{name: name})` clauses because Elixir pattern-matches top-down and `"*"` would otherwise match the generic string clause.

**Also update the `@doc` for `discover/1`** (lines 113-123) to mention wildcard:
```
- `%{capability: "*"}` — return ALL registered agents (wildcard)
- `%{name: "*"}` — return ALL registered agents (wildcard)
```

**Tests** (behaviors):
- Given 2 registered agents, when `discover(%{capability: "*"})`, then returns both agents as `{:ok, [agent_info(), agent_info()]}`
- Given 2 registered agents, when `discover(%{name: "*"})`, then returns both agents as `{:ok, [agent_info(), agent_info()]}`
- Given 0 registered agents, when `discover(%{capability: "*"})`, then returns `{:ok, []}`
- Given 2 registered agents, when wildcard discover, then each agent has keys `:id`, `:name`, `:capabilities`, `:description` (same shape as regular discover)

**Commands**:
```bash
mix test test/viche/agents_test.exs
```

**Dependencies**: None (can start immediately)

**Must NOT do**:
- Modify `list_agents/0`, `find_by_capability/1`, or `find_by_name/1`
- Add any new private helpers
- Change the return type of `discover/1`

**Pattern Reference**: Follow existing `discover/1` clause structure at `lib/viche/agents.ex:125-133`

**TDD Gates**:
- RED: Write 4 failing tests for wildcard discover in `test/viche/agents_test.exs`
- GREEN: Add 2 function clauses in `lib/viche/agents.ex`
- VALIDATE: `mix test test/viche/agents_test.exs`

---

### Phase 2: Verify HTTP controller works automatically (passthrough)

**Files** (CONFIRMED):
- `test/viche_web/controllers/registry_controller_test.exs` — Add wildcard tests inside existing `describe "GET /registry/discover"` block
- `lib/viche_web/controllers/registry_controller.ex` — NO changes expected (verify passthrough)

**Why no code changes**: `build_discover_query/1` at line 82-88 already extracts `params["capability"]` as a plain string. When `"*"` is passed, it becomes `%{capability: "*"}` which hits the new `discover/1` clause from Phase 1. The controller is a thin adapter.

**Tests** (behaviors):
- Given 2 registered agents, when `GET /registry/discover?capability=*`, then returns 200 with both agents in `agents` array
- Given 2 registered agents, when `GET /registry/discover?name=*`, then returns 200 with both agents in `agents` array
- Given 0 registered agents (after clearing), when `GET /registry/discover?capability=*`, then returns 200 with empty `agents` array

**Commands**:
```bash
mix test test/viche_web/controllers/registry_controller_test.exs
```

**Dependencies**: Phase 1 (needs wildcard clauses in `Viche.Agents`)

**Must NOT do**:
- Modify `registry_controller.ex` (this phase proves the passthrough works)
- Add new routes or controller actions

**Pattern Reference**: Follow existing discover tests at `test/viche_web/controllers/registry_controller_test.exs:127-230`

**TDD Gates**:
- RED: Write 3 failing tests (they fail because Phase 1 isn't done yet, or pass if Phase 1 is done — either way, write them)
- GREEN: Phase 1 implementation makes these pass automatically
- VALIDATE: `mix test test/viche_web/controllers/registry_controller_test.exs`

---

### Phase 3: Verify WebSocket channel works automatically (passthrough)

**Files** (CONFIRMED):
- `test/viche_web/channels/agent_channel_test.exs` — Add wildcard tests inside existing `describe "handle_in/3 - discover"` block
- `lib/viche_web/channels/agent_channel.ex` — NO changes expected (verify passthrough)

**Why no code changes**: The existing `handle_in("discover", %{"capability" => cap}, socket)` at line 59 already captures `"*"` as `cap` and passes it to `Agents.discover(%{capability: cap})`. Same for the name clause at line 64. The new `discover/1` wildcard clauses from Phase 1 handle the rest.

**Tests** (behaviors):
- Given 2 registered agents and a connected channel, when push `"discover"` with `%{"capability" => "*"}`, then reply is `{:ok, %{agents: [_, _]}}` containing both agents
- Given 2 registered agents and a connected channel, when push `"discover"` with `%{"name" => "*"}`, then reply is `{:ok, %{agents: [_, _]}}` containing both agents

**Commands**:
```bash
mix test test/viche_web/channels/agent_channel_test.exs
```

**Dependencies**: Phase 1 (needs wildcard clauses in `Viche.Agents`)

**Must NOT do**:
- Modify `agent_channel.ex` (this phase proves the passthrough works)
- Add new channel events

**Pattern Reference**: Follow existing channel discover tests at `test/viche_web/channels/agent_channel_test.exs:47-79`

**TDD Gates**:
- RED: Write 2 failing tests
- GREEN: Phase 1 implementation makes these pass automatically
- VALIDATE: `mix test test/viche_web/channels/agent_channel_test.exs`

---

### Phase 4: Update well-known descriptor documentation

**Files** (CONFIRMED):
- `lib/viche_web/controllers/well_known_controller.ex` — Update `@descriptor` map at lines 36-43 and line 94
- `test/viche_web/controllers/well_known_controller_test.exs` — Add test verifying wildcard is documented

**Implementation Detail**:

1. Update `discover` endpoint description (line 39):
   ```elixir
   description: "Find agents by capability or name. Pass \"*\" as capability or name to return all agents.",
   ```

2. Update `query_params` descriptions (lines 41-42):
   ```elixir
   capability: %{type: "string", description: "Find agents with this capability. Use \"*\" to return all agents."},
   name: %{type: "string", description: "Find agents with this exact name. Use \"*\" to return all agents."}
   ```

3. Update `client_events.discover` description (line 94):
   ```elixir
   discover: "Discover agents by capability or name. Payload: {capability, name}. Use \"*\" as value to return all agents.",
   ```

**Tests** (behaviors):
- Given the well-known endpoint, when `GET /.well-known/agent-registry`, then the discover endpoint description mentions wildcard `"*"`
- Given the well-known endpoint, when `GET /.well-known/agent-registry`, then the discover query_params capability description mentions `"*"`
- Given the well-known endpoint, when `GET /.well-known/agent-registry`, then the discover query_params name description mentions `"*"`

**Commands**:
```bash
mix test test/viche_web/controllers/well_known_controller_test.exs
```

**Dependencies**: None (independent of Phase 1 — this is documentation only)

**Must NOT do**:
- Add new endpoints to the descriptor
- Change the descriptor structure
- Modify any non-discover sections

**Pattern Reference**: Follow existing descriptor structure at `lib/viche_web/controllers/well_known_controller.ex:8-135`

**TDD Gates**:
- RED: Write 3 failing tests checking for wildcard mentions in descriptor strings
- GREEN: Update `@descriptor` string values
- VALIDATE: `mix test test/viche_web/controllers/well_known_controller_test.exs`

---

### Phase 5: Update TypeScript client tool descriptions

**Files** (CONFIRMED):
- `channel/viche-channel.ts` — Update `viche_discover` tool description (lines 203-211)
- `channel/openclaw-plugin-viche/tools.ts` — Update `viche_discover` tool description (lines 86-94)

**Implementation Detail**:

1. In `channel/viche-channel.ts`, update the `viche_discover` tool:
   - Update `description` (line 203-204) to:
     ```typescript
     description:
       "Discover other AI agents on the Viche network by capability. Pass '*' to list all agents. Returns a list of agents that match.",
     ```
   - Update `capability` property description (lines 209-210) to:
     ```typescript
     description:
       "Capability to search for (e.g. 'coding', 'research', 'code-review'). Use '*' to return all agents.",
     ```

2. In `channel/openclaw-plugin-viche/tools.ts`, update the `viche_discover` tool:
   - Update `description` (lines 87-89) to:
     ```typescript
     description:
       "Discover AI agents registered on the Viche network by capability. " +
       "Pass '*' to list all agents. " +
       "Returns a list of agents that match the requested capability string. " +
       "Use this before sending a message to find the target agent ID.",
     ```
   - Update `capability` TypeBox description (lines 92-93) to:
     ```typescript
     description:
       "Capability to search for (e.g. 'coding', 'research', 'code-review', 'testing'). Use '*' to return all agents.",
     ```

**Tests**: No automated tests for TypeScript description strings (manual verification only).

**Commands**:
```bash
# Verify TypeScript compiles (if bun/tsc available)
cd channel && bun build viche-channel.ts --outdir=dist 2>&1 | head -5
```

**Dependencies**: None (independent — description-only changes)

**Must NOT do**:
- Change tool input schemas (capability remains required string)
- Change tool execution logic
- Add new tools
- Modify `viche_send` or `viche_reply` tools

**Pattern Reference**: Follow existing tool description style in each file

**TDD Gates**:
- RED: N/A (no automated tests for TS descriptions)
- GREEN: Update description strings
- VALIDATE: Verify TypeScript compiles without errors

---

## What We're NOT Doing

| Excluded Feature | Reason |
|-----------------|--------|
| Glob patterns (`"code*"`) | Over-engineering; `"*"` covers the "list all" use case |
| Regex matching | Security risk + complexity; not requested |
| Pagination for wildcard results | Premature optimization; agent count is small |
| Rate limiting on wildcard | No evidence of abuse vector; agents are authenticated |
| New `/registry/list` endpoint | `discover?capability=*` is sufficient; no new API surface |
| Making `capability` optional in TS clients | Would break existing tool contract; `"*"` is a valid string value |

---

## Risks and Mitigations

| Risk | Trigger | Mitigation |
|------|---------|------------|
| Clause ordering bug | New wildcard clause placed AFTER generic clause | Elixir compiler warns about unreachable clauses; tests catch it |
| Large agent list performance | Thousands of agents registered | Out of scope; `list_agents/0` already exists with same perf profile |
| `"*"` used as actual capability name | Agent registers with `capabilities: ["*"]` | Acceptable edge case — they'd appear in wildcard results anyway |

---

## Success Criteria

### Verification Commands
```bash
# Run all affected test files
mix test test/viche/agents_test.exs test/viche_web/controllers/registry_controller_test.exs test/viche_web/channels/agent_channel_test.exs test/viche_web/controllers/well_known_controller_test.exs

# Run full precommit (compilation, formatting, Credo, tests, Dialyzer)
mix precommit
```

### Final Checklist
- [ ] `discover(%{capability: "*"})` returns all agents
- [ ] `discover(%{name: "*"})` returns all agents
- [ ] `GET /registry/discover?capability=*` returns all agents (HTTP)
- [ ] Channel push `discover` with `capability: "*"` returns all agents (WebSocket)
- [ ] Well-known descriptor documents wildcard behavior
- [ ] Both TypeScript clients mention wildcard in tool descriptions
- [ ] All existing discover tests still pass (no regressions)
- [ ] `mix precommit` passes
