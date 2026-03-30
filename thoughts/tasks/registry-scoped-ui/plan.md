# Registry-Scoped UI with Sidebar Selector

## TL;DR

> **Summary**: Scope the Viche UI to show agents per-registry instead of all agents globally. Add a config-driven registry selector to the sidebar that lets dev/self-hosted users pick which registry to view.
> **Deliverables**: `list_agents_with_status/1` with registry filter, `list_registries/0`, `public_mode` config flag, registry selector in sidebar, PubSub re-subscription on registry change
> **Effort**: Medium (1-2d)
> **Parallel Execution**: NO - sequential (each phase builds on prior)

---

## Context

### Original Request
The Viche UI (`AgentsLive`, `NetworkLive`, `DashboardLive`, `SessionsLive`) calls `Viche.Agents.list_agents_with_status/0` which returns ALL agents across ALL registries. This makes it look like every agent is in the global registry, even those in private registries. The backend `discover/1` already scopes correctly — the bug is purely in the UI layer.

### Research Findings (Wave 0-1)
| Source | Finding | Implication |
|--------|---------|-------------|
| `lib/viche/agents.ex:57-96` | `list_agents_with_status/0` calls `all_agents()` with no registry filter | Must add `/1` variant that filters by registry |
| `lib/viche/agents.ex:371-398` | `agents_in_registry/1` already filters by `registry in agent_registries(meta)` | Reuse this pattern for the new function |
| `lib/viche/agents.ex:355-358` | `all_agents/1` returns `[{id, meta}]` where `meta.registries` exists | Registry data already available in metadata |
| `lib/viche/agents.ex:495-506` | `broadcast_agent_joined/1` broadcasts to each agent's registries | PubSub topics already per-registry |
| 6 LiveView templates | Sidebar is duplicated across `dashboard_live`, `agents_live`, `network_live`, `sessions_live`, `settings_live`, `agent_detail_live` | Add selector to each; do NOT extract sidebar (Oracle recommendation) |
| `config/dev.exs:71` | `config :viche, dev_routes: true` pattern exists | Follow same pattern for `public_mode` |
| `lib/viche/agent_server.ex:251` | `Application.get_env(:viche, :grace_period_ms, 60_000)` pattern | Follow same pattern for config access |
| `lib/viche_web/components/core_components.ex:236-255` | `<select>` component exists in core_components | Can use for registry dropdown |
| `thoughts/tasks/private-registries/` | Private registries v0.2.0 already shipped | Registry infrastructure is stable |

### Interview Decisions
- Config key: `config :viche, :public_mode, false` (default)
- In prod (`public_mode: true`): UI locked to `"global"`, selector hidden
- In dev (`public_mode: false`): Selector visible, user picks registry
- Metrics (`agent_count`, `online_count`) stay global regardless of filter
- `messages_today` stays global
- Default selected registry: `"global"` (not `:all`)

### Oracle Review Summary
- Do NOT extract sidebar as prerequisite — add selector to each duplicated sidebar
- Put state/subscription logic before UI rollout
- Watch for subscription leaks (unsubscribe old before subscribing new)
- Registry list is volatile (derived from live agents) — acceptable for v1
- Keep `public_mode` strictly UI-scoping, no API behavior changes

---

## Objectives

### Core Objective
Make the Viche UI registry-aware: show only agents belonging to the selected registry, with a config-driven selector that is hidden in production (locked to global) and visible in dev/self-hosted mode.

### Scope
| IN (Must Ship) | OUT (Explicit Exclusions) |
|----------------|---------------------------|
| `list_agents_with_status/1` with registry filter | Auth/authorization for registry access |
| `list_registries/0` function | Per-registry metrics (counts stay global) |
| `public_mode` config flag | REST API changes |
| Registry selector in sidebar (6 LiveViews) | WebSocket channel changes |
| PubSub re-subscription on registry change | Plugin code changes (OpenCode/OpenClaw) |
| Tests for all new behavior | Full sidebar extraction/refactor |

### Definition of Done
- [ ] `Viche.Agents.list_agents_with_status("global")` returns only agents in the global registry
- [ ] `Viche.Agents.list_agents_with_status(:all)` returns all agents (current behavior)
- [ ] `Viche.Agents.list_registries()` returns unique sorted registry tokens from live agents
- [ ] When `public_mode: true`, no registry selector is visible in the UI
- [ ] When `public_mode: false`, registry selector is visible and functional
- [ ] Switching registries updates the agent list in real-time
- [ ] PubSub subscriptions update when registry selection changes
- [ ] `agent_count` and `online_count` in sidebar remain global totals
- [ ] All tests pass: `mix test`
- [ ] All quality gates pass: `mix precommit`

### Must NOT Have (Guardrails)
- No changes to REST API endpoints or WebSocket channels
- No changes to plugin code (OpenCode/OpenClaw/MCP)
- No full sidebar extraction (defer to follow-up ticket)
- No persisted registry catalog (derived from live agents is fine for v1)
- No per-registry metrics or counters
- No auth/authorization gating on registry access

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: YES — `test/viche/agents_test.exs` has established patterns
- **Approach**: TDD (RED-GREEN-VALIDATE-REFACTOR per phase)
- **Framework**: ExUnit with `start_supervised!/1` for process tests

### Test Files
- `test/viche/agents_test.exs` — extend with `list_agents_with_status/1` and `list_registries/0` tests
- `test/viche_web/live/agents_live_test.exs` — NEW: LiveView tests for registry selector

---

## Execution Phases

### Dependency Graph
```
Phase 1 (domain: filter + list_registries) ──> Phase 2 (config flag)
Phase 2 ──> Phase 3 (LiveView state + PubSub wiring)
Phase 3 ──> Phase 4 (UI selector in sidebar)
```

### Phase 1: Add `list_agents_with_status/1` and `list_registries/0` to `Viche.Agents`

**Files** (CONFIRMED by research):
- `lib/viche/agents.ex` — Add `list_agents_with_status/1` function (accepts `:all` atom or registry token string), add `list_registries/0` function
- `test/viche/agents_test.exs` — Add test describe blocks for both new functions

**Implementation Notes**:
- `list_agents_with_status/1` should delegate to existing `list_agents_with_status/0` when given `:all`, and filter using the same pattern as `agents_in_registry/1` (line 372-377) when given a string token
- `list_registries/0` should scan `all_agents(Viche.AgentRegistry)`, extract `meta.registries` from each, flatten, deduplicate with `Enum.uniq/1`, and sort
- Keep `list_agents_with_status/0` as-is (backwards compatible) — the `/1` variant is additive
- The `registries` field is already in Registry metadata (confirmed at `agents.ex:464`)

**Tests** (behaviors, not names):
- Given agents in `["global"]` and `["team-alpha"]`, when `list_agents_with_status("global")`, then returns only the global agent
- Given agents in `["global"]` and `["team-alpha"]`, when `list_agents_with_status("team-alpha")`, then returns only the team-alpha agent
- Given agents in `["global", "team-alpha"]` (multi-registry), when `list_agents_with_status("global")`, then includes that agent
- Given agents in `["global", "team-alpha"]` (multi-registry), when `list_agents_with_status("team-alpha")`, then includes that agent
- Given agents in `["global"]` and `["team-alpha"]`, when `list_agents_with_status(:all)`, then returns both agents
- Given no agents, when `list_registries()`, then returns `[]`
- Given agents in `["global"]` and `["global", "team-alpha"]`, when `list_registries()`, then returns `["global", "team-alpha"]` (sorted, unique)

**Commands**:
```bash
mix test test/viche/agents_test.exs
mix precommit
```

**Dependencies**: None (can start immediately)

**Must NOT do**:
- Remove or change `list_agents_with_status/0` signature
- Add any web layer code
- Add config reading

**Pattern Reference**: Follow `agents_in_registry/1` at `lib/viche/agents.ex:372-377` for registry filtering logic. Follow `all_agents/1` at `lib/viche/agents.ex:356-358` for Registry scan.

**TDD Gates**:
- RED: Write failing tests for `list_agents_with_status/1` with registry filter and `list_registries/0`
- GREEN: Implement minimal filtering logic reusing `agent_registries/1` pattern
- VALIDATE: `mix test test/viche/agents_test.exs` passes, then `mix precommit`
- REFACTOR: Extract shared enrichment logic if `list_agents_with_status/0` and `/1` share code

---

### Phase 2: Add `public_mode` config flag

**Files** (CONFIRMED by research):
- `config/config.exs` — Add `config :viche, :public_mode, false` (line ~12, after `generators` config)
- `config/runtime.exs` — Add `config :viche, :public_mode, true` inside the `if config_env() == :prod do` block (after line 57)
- `test/viche/agents_test.exs` — Add test for config reading helper (optional, config is trivial)

**Implementation Notes**:
- Follow existing pattern: `Application.get_env(:viche, :public_mode, false)` (same as `grace_period_ms` pattern at `agent_server.ex:251`)
- No new module needed — LiveViews will read config directly via `Application.get_env/3`
- In `runtime.exs`, also support `VICHE_PUBLIC_MODE` env var for flexibility:
  ```elixir
  if System.get_env("VICHE_PUBLIC_MODE") in ~w(true 1),
    do: config(:viche, :public_mode, true)
  ```

**Tests** (behaviors, not names):
- Given `config :viche, :public_mode, false`, when `Application.get_env(:viche, :public_mode, false)`, then returns `false`
- Given `config :viche, :public_mode, true`, when `Application.get_env(:viche, :public_mode, false)`, then returns `true`

**Commands**:
```bash
mix test
mix precommit
```

**Dependencies**: None (independent of Phase 1, but ordered for clarity)

**Must NOT do**:
- Add any web layer code yet
- Change API behavior based on this flag
- Add the flag to any module other than config files

**Pattern Reference**: Follow `config :viche, dev_routes: true` in `config/dev.exs:71` and `Application.get_env(:viche, :grace_period_ms, 60_000)` in `lib/viche/agent_server.ex:251`.

**TDD Gates**:
- RED: N/A (config is declarative, no test needed for config files themselves)
- GREEN: Add config lines to both files
- VALIDATE: `mix precommit` passes (compilation, no warnings)
- REFACTOR: N/A

---

### Phase 3: Wire LiveView state management and PubSub re-subscription

**Files** (CONFIRMED by research):
- `lib/viche_web/live/agents_live.ex` — Add `selected_registry` assign, modify `load_agents/1` to use `list_agents_with_status/1`, add `handle_event("select_registry", ...)`, manage PubSub subscriptions
- `lib/viche_web/live/dashboard_live.ex` — Same pattern: add `selected_registry` assign, modify `load_and_assign_agents/1`
- `lib/viche_web/live/network_live.ex` — Same pattern: add `selected_registry` assign, modify agent loading
- `lib/viche_web/live/sessions_live.ex` — Same pattern: add `selected_registry` assign, modify `load_inboxes/1`
- `lib/viche_web/live/settings_live.ex` — Add `selected_registry` assign (for sidebar consistency)
- `lib/viche_web/live/agent_detail_live.ex` — Add `selected_registry` assign, modify `load_sidebar_counts/1`

**Implementation Notes**:
- Each LiveView gets these new assigns in `mount/3`:
  - `selected_registry` — defaults to `"global"`
  - `public_mode` — read from `Application.get_env(:viche, :public_mode, false)`
  - `registries` — populated from `Viche.Agents.list_registries()`
- `handle_event("select_registry", %{"registry" => token}, socket)`:
  1. Unsubscribe from old registry topic: `Phoenix.PubSub.unsubscribe(Viche.PubSub, "registry:#{old_registry}")` — but only if old was not `:all`
  2. Subscribe to new registry topic: `Phoenix.PubSub.subscribe(Viche.PubSub, "registry:#{new_registry}")`
  3. If "all" selected: subscribe to ALL registry topics from `list_registries/0`
  4. Update `selected_registry` assign
  5. Reload agents with new filter
- `handle_info` for `agent_joined`/`agent_left` must also refresh `registries` assign (selector options may change)
- **Metrics stay global**: `agent_count` and `online_count` always use `list_agents_with_status(:all)` regardless of selected registry. The filtered list is only for the agent display.
- For `AgentsLive` specifically:
  - `load_agents/1` changes: `all = Viche.Agents.list_agents_with_status(socket.assigns.selected_registry)` for display
  - But `agent_count`/`online_count` use `Viche.Agents.list_agents_with_status(:all)` for sidebar metrics

**Tests** (behaviors, not names):
- Given `public_mode: false` and agents in multiple registries, when LiveView mounts, then `selected_registry` is `"global"` and only global agents shown
- Given `public_mode: true`, when LiveView mounts, then `selected_registry` is `"global"` (locked)
- Given `public_mode: false`, when user selects "team-alpha" registry, then agent list updates to show only team-alpha agents
- Given registry switch from "global" to "team-alpha", when new agent joins "global", then LiveView does NOT update agent list (unsubscribed from global)
- Given registry switch from "global" to "team-alpha", when new agent joins "team-alpha", then LiveView DOES update agent list
- Given agents in multiple registries, when any registry selected, then `agent_count` and `online_count` remain global totals

**Commands**:
```bash
mix test test/viche_web/live/agents_live_test.exs
mix test
mix precommit
```

**Dependencies**: Phase 1 (needs `list_agents_with_status/1` and `list_registries/0`), Phase 2 (needs `public_mode` config)

**Must NOT do**:
- Change sidebar HTML structure (that's Phase 4)
- Add any REST API changes
- Persist selected registry to database
- Change `agent_count`/`online_count` to be registry-scoped

**Pattern Reference**: Follow existing `handle_info` pattern in `agents_live.ex:48-54` for broadcast handling. Follow `Phoenix.PubSub.subscribe/2` pattern at `agents_live.ex:7-8`.

**TDD Gates**:
- RED: Write LiveView tests that assert `selected_registry` assign exists, agent filtering works, PubSub re-subscription works
- GREEN: Implement state management in each LiveView
- VALIDATE: `mix test` passes, then `mix precommit`
- REFACTOR: Extract shared registry-selection helpers into a private function or use a shared module if duplication is excessive across 6 LiveViews

---

### Phase 4: Add registry selector UI to sidebar in all LiveViews

**Files** (CONFIRMED by research):
- `lib/viche_web/live/agents_live.html.heex` — Add registry selector dropdown in sidebar (after "Agents" section header, before nav items, ~line 30-35)
- `lib/viche_web/live/dashboard_live.html.heex` — Same selector placement
- `lib/viche_web/live/network_live.html.heex` — Same selector placement
- `lib/viche_web/live/sessions_live.html.heex` — Same selector placement
- `lib/viche_web/live/settings_live.html.heex` — Same selector placement
- `lib/viche_web/live/agent_detail_live.html.heex` — Same selector placement

**Implementation Notes**:
- The selector is a `<select>` element styled to match the sidebar theme:
  ```heex
  <%= unless @public_mode do %>
    <div class="px-2 mb-1">
      <select
        id="registry-selector"
        phx-change="select_registry"
        name="registry"
        class="w-full text-[11px] font-mono rounded px-2 py-1"
        style="background:var(--bg-2);color:var(--fg);border:1px solid var(--border)"
      >
        <option value="global" selected={@selected_registry == "global"}>global</option>
        <option :for={reg <- @registries} :if={reg != "global"} value={reg} selected={@selected_registry == reg}>
          {reg}
        </option>
        <option value="all" selected={@selected_registry == :all}>All registries</option>
      </select>
    </div>
  <% end %>
  ```
- Place this AFTER the "Agents" section header div and BEFORE the first agent nav item
- When `@public_mode` is `true`, the entire selector block is not rendered
- The "All registries" option sends `"all"` which the `handle_event` converts to `:all`
- Sidebar metrics (`@agent_count`, `@online_count`) are NOT affected by selection (they show global totals)

**Tests** (behaviors, not names):
- Given `public_mode: false`, when page renders, then registry selector element is present in DOM
- Given `public_mode: true`, when page renders, then registry selector element is NOT present in DOM
- Given agents in `["global", "team-alpha"]`, when page renders with `public_mode: false`, then selector shows "global", "team-alpha", and "All registries" options
- Given `public_mode: false` and "team-alpha" selected, when page renders, then only team-alpha agents are displayed in the main content area
- Given `public_mode: false`, when user changes selector to "team-alpha", then agent list updates without full page reload (LiveView patch)

**Commands**:
```bash
mix test test/viche_web/live/agents_live_test.exs
mix test
mix precommit
```

**Dependencies**: Phase 3 (needs `selected_registry`, `public_mode`, `registries` assigns and `handle_event("select_registry", ...)`)

**Must NOT do**:
- Extract sidebar into shared component (defer to follow-up)
- Change sidebar navigation structure or styling
- Add registry selector to non-LiveView pages (landing, join)
- Change metrics display to be registry-scoped

**Pattern Reference**: Follow existing `<select>` component pattern in `lib/viche_web/components/core_components.ex:236-255`. Follow sidebar styling at `agents_live.html.heex:2-92`.

**TDD Gates**:
- RED: Write LiveView tests asserting selector presence/absence based on `public_mode`, and option population
- GREEN: Add selector HTML to all 6 sidebar templates
- VALIDATE: `mix test` passes, then `mix precommit`
- REFACTOR: If selector HTML is identical across all 6 templates, consider extracting a small `registry_selector/1` function component (but NOT full sidebar extraction)

---

## Risks and Mitigations

| Risk | Trigger | Mitigation |
|------|---------|------------|
| PubSub subscription leak | User rapidly switches registries | Unsubscribe old topic before subscribing new; track subscribed topics in assign |
| Registry list volatility | Agent deregisters, registry disappears from selector | Acceptable for v1; selector updates reactively via `agent_joined`/`agent_left` handlers |
| Sidebar duplication drift | 6 copies of selector diverge | Keep selector HTML minimal; consider extracting `registry_selector/1` component in Phase 4 refactor step |
| `public_mode` semantics creep | Someone uses flag to gate API behavior | Guardrail: flag is read ONLY in LiveView mount, nowhere else |
| Double-subscribe on mount | `connected?` callback fires twice | Phoenix guarantees single connected mount; existing pattern is safe |
| Metrics confusion | User expects counts to reflect selected registry | Document clearly: sidebar counts are always global |

---

## Success Criteria

### Verification Commands
```bash
# Run domain tests
mix test test/viche/agents_test.exs

# Run LiveView tests
mix test test/viche_web/live/agents_live_test.exs

# Run all tests
mix test

# Run full quality gate
mix precommit
```

### Final Checklist
- [ ] `list_agents_with_status/1` filters by registry correctly
- [ ] `list_agents_with_status(:all)` returns all agents (backwards compatible)
- [ ] `list_agents_with_status/0` still works unchanged
- [ ] `list_registries/0` returns sorted unique tokens
- [ ] `public_mode: true` hides selector, locks to global
- [ ] `public_mode: false` shows selector with dynamic options
- [ ] Registry switch updates agent list in real-time
- [ ] PubSub re-subscribes on registry change
- [ ] Sidebar metrics remain global totals
- [ ] All tests pass: `mix test`
- [ ] All quality gates pass: `mix precommit`
