# OpenCode Plugin: Viche Agent Network

## TL;DR

> **Summary**: Build an OpenCode native plugin that registers agents on the Viche network, enables real-time multi-agent communication via 3 tools + WebSocket inbound injection, and includes a SKILL.md for agent behavior instructions.
> **Deliverables**: Plugin (6 files), Skill (1 file), Config integration, README
> **Effort**: Medium (1-2d)
> **Parallel Execution**: NO — sequential (each phase builds on prior)

---

## Context

### Original Request
Create an OpenCode plugin (`opencode-plugin-viche`) that connects OpenCode agents to the Viche agent network, enabling real-time multi-agent communication. Third client adapter after Claude Code and OpenClaw.

### Research Findings (Wave 0-1)

| Source | Finding | Implication |
|--------|---------|-------------|
| `channel/viche-channel.ts` | Claude Code uses MCP stdio, 3 tools via Channel push, inbound via `server.notification()` | Different injection mechanism; tool schemas are consistent |
| `channel/openclaw-plugin-viche/` | OpenClaw uses native plugin, background service, 3 tools via HTTP REST, inbound via `runtime.subagent.run()` | Closest architectural match — model after this |
| `@opencode-ai/plugin` v1.3.2 | `Plugin = (PluginInput) => Promise<Hooks>`, `tool()` helper with Zod, `event` hook, `client.session.prompt()` | Single-process plugin is viable (no sidecar needed) |
| `@opencode-ai/sdk` types | `SessionPromptData` has `noReply`, `parts`, `path.id`; `ToolContext` has `sessionID` | Tools know their session; injection API is typed |
| `specs/10-opencode-bridge.md` | Original spec proposed two-component sidecar | **Superseded** — plugin system provides session awareness |
| Oracle consultation | Per-session agents, HTTP for tools, WS for inbound, `ensureSessionReady()` gate | Architecture validated |

### Interview Decisions
- **Architecture**: Single-process plugin (not two-component sidecar) — Oracle validated
- **Registration**: Per-session agents (one Viche agent per OpenCode session)
- **Tool transport**: HTTP REST for outbound tools (not WebSocket)
- **Inbound transport**: WebSocket Channel for real-time message push
- **Injection API**: `client.session.promptAsync()` with intent-based `noReply`
- **Config**: File (`.opencode/viche.json`) + env vars, env overrides file

### Defaults Applied
- Following pattern from `channel/openclaw-plugin-viche/` for structure and conventions
- TDD approach with tests alongside implementation
- No breaking changes to existing Viche server
- Backwards compatible with existing Claude Code and OpenClaw clients

---

## Objectives

### Core Objective
Enable OpenCode agents to participate in the Viche agent network by registering, discovering peers, sending/receiving messages, and responding to tasks — all through a native OpenCode plugin.

### Scope

| IN (Must Ship) | OUT (Explicit Exclusions) |
|----------------|---------------------------|
| Plugin entry point with event + tool hooks | npm publishing / CI/CD pipeline |
| Config loading (file + env vars + defaults) | Multi-registry support |
| Per-session agent registration + WebSocket | Authentication / token refresh |
| 3 tools: viche_discover, viche_send, viche_reply | Message persistence / durability |
| Inbound message injection via `promptAsync()` | Guaranteed exactly-once delivery |
| Session lifecycle management (create/delete) | Cross-instance shared state |
| SKILL.md for agent behavior instructions | Advanced retry orchestration |
| README.md with setup instructions | UI components / dashboard |
| `.opencode/plugins/viche.ts` re-export for local dev | Rate limiting / backpressure |

### Definition of Done
- [ ] Plugin loads in OpenCode without errors
- [ ] Agent registers on Viche network when session starts
- [x] `viche_discover` returns agents matching capability
- [x] `viche_send` delivers message to target agent
- [x] `viche_reply` sends result-type message back
- [ ] Inbound WebSocket messages are injected into correct session
- [ ] Agent cleans up on session deletion
  - [x] Config loads from file, env vars, and defaults
- [ ] SKILL.md instructs agent on Viche protocol
- [ ] All tests pass

### Must NOT Have (Guardrails)
- No sidecar daemon — everything runs in-process
- No `my_agent_id` tool parameter — agent ID is resolved from session state
- No hardcoded agent name/capabilities — all configurable
- No direct GenServer/AgentServer interaction — only HTTP + WebSocket
- No inline `<script>` tags or browser-side code
- No message persistence or queue — fire-and-forget with logging

---

## Verification Strategy

### Test Decision
- **Infrastructure exists**: YES — Bun test runner available
- **Approach**: TDD (RED → GREEN → VALIDATE)
- **Framework**: `bun test` with TypeScript

### Test Structure
```
channel/opencode-plugin-viche/
├── __tests__/
│   ├── config.test.ts      # Config loading tests
│   ├── service.test.ts     # Session lifecycle tests
│   ├── tools.test.ts       # Tool behavior tests
│   └── index.test.ts       # Plugin integration tests
```

---

## Execution Phases

### Dependency Graph
```
Phase 1 (types.ts — no deps)
  └──> Phase 2 (config.ts — needs types)
         └──> Phase 3 (service.ts — needs config + types)
                └──> Phase 4 (tools.ts — needs service + types)
                       └──> Phase 5 (index.ts — needs all)
                              └──> Phase 6 (SKILL.md + README + wiring)
```

---

### Phase 1: Types and Package Setup

**Files** (NEW — under `channel/opencode-plugin-viche/`):
- `channel/opencode-plugin-viche/package.json` — Create package manifest with dependencies
- `channel/opencode-plugin-viche/tsconfig.json` — TypeScript config
- `channel/opencode-plugin-viche/types.ts` — Create shared type definitions

**Types to define** (model after `channel/openclaw-plugin-viche/types.ts`):
```typescript
// Config shape
interface VicheConfig {
  registryUrl: string;       // default: "http://localhost:4000"
  capabilities: string[];    // default: ["coding"]
  agentName?: string;        // optional
  description?: string;      // optional
}

// Per-session state
interface SessionState {
  agentId: string;
  socket: PhoenixSocket;     // from phoenix npm package
  channel: PhoenixChannel;
}

// Global plugin state
interface VicheState {
  sessions: Map<string, SessionState>;       // sessionID → SessionState
  initializing: Map<string, Promise<SessionState>>; // in-flight inits (race guard)
}

// API response types
interface RegisterResponse { id: string; }
interface AgentInfo { id: string; name?: string; capabilities?: string[]; description?: string; }
interface DiscoverResponse { agents: AgentInfo[]; }
interface InboundMessagePayload { id: string; from: string; body: string; type: string; }
```

**Package dependencies**:
- `phoenix` — Phoenix Channel WebSocket client
- `@opencode-ai/plugin` — Plugin SDK (peer dependency)
- `@opencode-ai/sdk` — SDK types (peer dependency)

**Tests** (`__tests__/types.test.ts` — optional, types are compile-time):
- Given the types module, when imported, then all interfaces are accessible
- Given VicheState, when created, then sessions and initializing maps are empty

**Commands**:
```bash
cd channel/opencode-plugin-viche && bun install
cd channel/opencode-plugin-viche && bun run tsc --noEmit
```

**Dependencies**: None (can start immediately)

**Must NOT do**:
- Add runtime validation to types (that's config.ts Phase 2)
- Import OpenCode SDK types directly (use type-only imports)

**Pattern Reference**: Follow `channel/openclaw-plugin-viche/types.ts` for naming conventions

---

### Phase 2: Config Loading

**Files**:
- `channel/opencode-plugin-viche/config.ts` — Create config loader
- `channel/opencode-plugin-viche/__tests__/config.test.ts` — Create config tests

**Config loading logic** (model after OpenClaw's config but adapted for OpenCode):

1. **File loading**: Read `.opencode/viche.json` (project-level) or `~/.config/opencode/viche.json` (global)
2. **Env var override**: `VICHE_REGISTRY_URL`, `VICHE_AGENT_NAME`, `VICHE_CAPABILITIES` (comma-separated), `VICHE_DESCRIPTION`
3. **Defaults**: `{ registryUrl: "http://localhost:4000", capabilities: ["coding"] }`
4. **Precedence**: env vars > file > defaults
5. **Validation**: registryUrl must be a string, capabilities must be non-empty string array

**Exported function**:
```typescript
export function loadConfig(projectDir: string): VicheConfig
```

**Tests** (`__tests__/config.test.ts`):
- Given no config file and no env vars, when loadConfig is called, then returns defaults (registryUrl=localhost:4000, capabilities=["coding"])
- Given a valid `.opencode/viche.json` file, when loadConfig is called, then returns file values
- Given env vars set, when loadConfig is called, then env vars override file values
- Given `VICHE_CAPABILITIES="coding,research,testing"`, when loadConfig is called, then capabilities is `["coding", "research", "testing"]`
- Given empty capabilities in config, when loadConfig is called, then falls back to default `["coding"]`
- Given invalid registryUrl type, when loadConfig is called, then falls back to default
- Given both file and env vars, when loadConfig is called, then env vars take precedence

**Commands**:
```bash
cd channel/opencode-plugin-viche && bun test __tests__/config.test.ts
```

**Dependencies**: Phase 1 (needs VicheConfig type)

**Must NOT do**:
- Throw on missing config file (it's optional)
- Add config schema validation beyond basic type checks
- Support YAML or TOML config formats

**Pattern Reference**: Follow env var parsing from `channel/viche-channel.ts:12-18` for VICHE_CAPABILITIES splitting

**TDD Gates**:
- RED: Write 7 failing tests for config loading scenarios
- GREEN: Implement `loadConfig()` to pass all tests
- VALIDATE: `bun test __tests__/config.test.ts` — all pass

---

### Phase 3: Service Layer (Session Lifecycle + WebSocket) ✅

**Files**:
- `channel/opencode-plugin-viche/service.ts` — Create session lifecycle manager
- `channel/opencode-plugin-viche/__tests__/service.test.ts` — Create service tests

**Service responsibilities**:

1. **`createVicheService(config, state, client)`** — factory that returns event handler functions
2. **`ensureSessionReady(sessionID)`** — idempotent session initialization:
   - Check if session already in `state.sessions` → return existing
   - Check if session in `state.initializing` → await existing promise
   - Otherwise: register agent → connect WebSocket → join channel → store state
   - Memoize the in-flight promise in `state.initializing` to prevent duplicate registrations
3. **`handleSessionCreated(sessionID)`** — calls `ensureSessionReady`, then injects identity context via `client.session.prompt({ path: { id: sessionID }, body: { noReply: true, parts: [{ type: "text", text: "..." }] } })`
4. **`handleSessionDeleted(sessionID)`** — leaves channel, disconnects socket, removes from maps
5. **`handleInboundMessage(sessionID, payload)`** — formats message, calls `client.session.promptAsync()`
6. **`shutdown()`** — cleanup all sessions on plugin unload

**Registration** (model after `channel/openclaw-plugin-viche/service.ts:42-64`):
```typescript
async function registerAgent(config: VicheConfig): Promise<string> {
  const body: Record<string, unknown> = { capabilities: config.capabilities };
  if (config.agentName) body.name = config.agentName;
  if (config.description) body.description = config.description;
  
  const resp = await fetch(`${config.registryUrl}/registry/register`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!resp.ok) throw new Error(`Registration failed: ${resp.status} ${resp.statusText}`);
  const data = await resp.json() as RegisterResponse;
  return data.id;
}
```

**Registration retry** (model after both existing implementations):
- `MAX_ATTEMPTS = 3`, `BACKOFF_MS = 2000`
- On final failure: throw (don't exit process — we're in-process with OpenCode)

**WebSocket connection** (model after `channel/openclaw-plugin-viche/service.ts:153-187`):
```typescript
const wsBase = config.registryUrl.replace(/^http/, "ws");
const socket = new Socket(`${wsBase}/socket/websocket`, { params: { agent_id: agentId } });
socket.connect();
const channel = socket.channel(`agent:${agentId}`, {});
channel.on("new_message", (payload) => handleInboundMessage(sessionID, payload));
// join with promise wrapper
```

**IMPORTANT WebSocket URL**: Use `/socket/websocket` (confirmed from `agent_socket.ex` and router). The Claude Code channel uses `/agent/websocket` which is WRONG — the actual Phoenix socket path is `/socket/websocket`.

**Identity injection** (on session created):
```typescript
await client.session.prompt({
  path: { id: sessionID },
  body: {
    noReply: true,
    parts: [{
      type: "text",
      text: `[Viche Network Connected] Your agent ID is ${agentId}. You are registered on the Viche agent network with capabilities: ${config.capabilities.join(", ")}. Use viche_discover to find other agents, viche_send to send tasks, and viche_reply to respond to tasks.`
    }]
  },
  query: { directory }
});
```

**Inbound message injection** (on WebSocket `new_message`):
```typescript
const label = payload.type === "result" ? "Result" : "Task";
const message = `[Viche ${label} from ${payload.from}] ${payload.body}`;

await client.session.promptAsync({
  path: { id: sessionID },
  body: {
    noReply: payload.type === "result",  // results = context only; tasks = trigger response
    parts: [{ type: "text", text: message }]
  },
  query: { directory }
});
```

**Tests** (`__tests__/service.test.ts`):
- Given a new session, when `ensureSessionReady` is called, then it registers an agent via HTTP POST to /registry/register
- Given a session already in state, when `ensureSessionReady` is called again, then it returns existing state without re-registering
- Given two concurrent calls to `ensureSessionReady` for the same session, when both execute, then only one registration occurs (dedup via initializing map)
- Given successful registration, when WebSocket connects, then channel joins `agent:{agentId}` topic
- Given a `session.created` event, when handled, then identity context is injected via `client.session.prompt` with `noReply: true`
- Given an inbound `new_message` with type "task", when handled, then message is injected via `client.session.promptAsync` with `noReply: false`
- Given an inbound `new_message` with type "result", when handled, then message is injected via `client.session.promptAsync` with `noReply: true`
- Given a `session.deleted` event, when handled, then channel is left, socket disconnected, and session removed from state
- Given registration fails after 3 attempts, when `ensureSessionReady` is called, then it throws an error (does not exit process)
- Given WebSocket channel join fails with `agent_not_found`, when connecting, then it re-registers and retries connection once

**Commands**:
```bash
cd channel/opencode-plugin-viche && bun test __tests__/service.test.ts
```

**Dependencies**: Phase 1 (types), Phase 2 (config)

**Must NOT do**:
- Call `process.exit()` on any failure (we're in-process with OpenCode)
- Implement custom WebSocket reconnection (rely on Phoenix client defaults)
- Add message persistence or queuing
- Handle more than one retry on `agent_not_found` recovery

**Pattern Reference**: Follow `channel/openclaw-plugin-viche/service.ts` for registration + WebSocket lifecycle

**TDD Gates**:
- RED: Write 10 failing tests for service lifecycle scenarios
- GREEN: Implement service functions to pass all tests (mock fetch + Phoenix Socket)
- VALIDATE: `bun test __tests__/service.test.ts` — all pass

---

### Phase 4: Tools (discover, send, reply)

**Files**:
- `channel/opencode-plugin-viche/tools.ts` — Create 3 tool definitions
- `channel/opencode-plugin-viche/__tests__/tools.test.ts` — Create tool tests

**Tool factory function**:
```typescript
export function createVicheTools(
  config: VicheConfig,
  state: VicheState,
  ensureSessionReady: (sessionID: string) => Promise<SessionState>
): Record<string, ToolDefinition>
```

Returns an object with 3 keys: `viche_discover`, `viche_send`, `viche_reply`.

#### Tool 1: `viche_discover`

**Zod schema**:
```typescript
args: {
  capability: tool.schema.string().describe(
    "Capability to search for (e.g. 'coding', 'research', 'code-review'). Use '*' to list all agents."
  ),
}
```

**Behavior**:
1. GET `${config.registryUrl}/registry/discover?capability=${encodeURIComponent(args.capability)}`
2. Parse response as `DiscoverResponse`
3. Format agent list as human-readable text
4. Return formatted string

**Note**: Discovery does NOT require session to be connected (no `ensureSessionReady` call). It's a stateless HTTP GET.

#### Tool 2: `viche_send`

**Zod schema**:
```typescript
args: {
  to: tool.schema.string().describe("Target agent ID (8-character hex string)"),
  body: tool.schema.string().describe("Message content"),
  type: tool.schema.string().optional().default("task").describe(
    "Message type: 'task' (default), 'result', or 'ping'"
  ),
}
```

**Behavior**:
1. Call `ensureSessionReady(context.sessionID)` to get `agentId`
2. POST `${config.registryUrl}/messages/${args.to}` with `{ from: sessionState.agentId, body: args.body, type: args.type ?? "task" }`
3. Return `"Message sent to ${args.to} (type: ${msgType})."`

#### Tool 3: `viche_reply`

**Zod schema**:
```typescript
args: {
  to: tool.schema.string().describe("Agent ID to reply to — copy from the 'from' field of the received message"),
  body: tool.schema.string().describe("Your result, answer, or response"),
}
```

**Behavior**:
1. Call `ensureSessionReady(context.sessionID)` to get `agentId`
2. POST `${config.registryUrl}/messages/${args.to}` with `{ from: sessionState.agentId, body: args.body, type: "result" }`
3. Return `"Reply sent to ${args.to}."`

**Shared helpers** (model after `channel/openclaw-plugin-viche/tools.ts`):
```typescript
function formatAgents(agents: AgentInfo[]): string {
  if (agents.length === 0) return "No agents found matching that capability.";
  const lines = agents.map((a) => {
    const caps = a.capabilities?.join(", ") ?? "none";
    const name = a.name ? ` (${a.name})` : "";
    const desc = a.description ? ` — ${a.description}` : "";
    return `• ${a.id}${name} — capabilities: ${caps}${desc}`;
  });
  return `Found ${agents.length} agent(s):\n${lines.join("\n")}`;
}
```

**Tests** (`__tests__/tools.test.ts`):
- Given capability "coding", when viche_discover is called, then it GETs /registry/discover?capability=coding and returns formatted agent list
- Given capability "*", when viche_discover is called, then it GETs /registry/discover?capability=* and returns all agents
- Given no agents match, when viche_discover is called, then it returns "No agents found matching that capability."
- Given a valid target agent, when viche_send is called, then it POSTs to /messages/:to with correct from/body/type
- Given no type specified, when viche_send is called, then type defaults to "task"
- Given type "ping", when viche_send is called, then type is "ping" in the POST body
- Given a valid target agent, when viche_reply is called, then it POSTs to /messages/:to with type "result"
- Given session not yet ready, when viche_send is called, then it calls ensureSessionReady and waits
- Given Viche registry unreachable, when viche_discover is called, then it returns error text (does not throw)
- Given HTTP 404 for target agent, when viche_send is called, then it returns "Agent not found" error text

**Commands**:
```bash
cd channel/opencode-plugin-viche && bun test __tests__/tools.test.ts
```

**Dependencies**: Phase 1 (types), Phase 3 (service — for `ensureSessionReady`)

**Must NOT do**:
- Add `my_agent_id` parameter to tools (agent ID comes from session state)
- Use WebSocket Channel pushes for tools (use HTTP REST)
- Throw errors from tool execute functions (return error text strings)
- Add caching to discovery results

**Pattern Reference**: Follow `channel/openclaw-plugin-viche/tools.ts` for tool structure and error handling

**TDD Gates**:
- RED: Write 10 failing tests for tool behaviors
- GREEN: Implement tools to pass all tests (mock fetch)
- VALIDATE: `bun test __tests__/tools.test.ts` — all pass

---

### Phase 5: Plugin Entry Point

**Files**:
- `channel/opencode-plugin-viche/index.ts` — Create plugin entry point
- `channel/opencode-plugin-viche/__tests__/index.test.ts` — Create integration tests

**Plugin structure** (model after `@opencode-ai/plugin` example + OpenClaw pattern):
```typescript
import type { Plugin } from "@opencode-ai/plugin";
import { loadConfig } from "./config.js";
import { createVicheService } from "./service.js";
import { createVicheTools } from "./tools.js";
import type { VicheState } from "./types.js";

const vichePlugin: Plugin = async ({ client, directory }) => {
  const config = loadConfig(directory);
  const state: VicheState = {
    sessions: new Map(),
    initializing: new Map(),
  };

  const service = createVicheService(config, state, client, directory);
  const tools = createVicheTools(config, state, service.ensureSessionReady);

  return {
    event: async ({ event }) => {
      if (event.type === "session.created") {
        const sessionID = event.properties?.info?.id;
        if (sessionID && !event.properties?.info?.parentID) {
          // Only register root sessions (not subtasks)
          await service.handleSessionCreated(sessionID);
        }
      }
      if (event.type === "session.deleted") {
        const sessionID = event.properties?.info?.id;
        if (sessionID) {
          await service.handleSessionDeleted(sessionID);
        }
      }
    },
    tool: tools,
  };
};

export default vichePlugin;
```

**Key design decisions**:
1. Only register root sessions (`!parentID`) — subtask sessions should NOT get their own Viche agent
2. Config is loaded once at plugin init, not per-session
3. State is shared between event handler and tools via closure
4. The `directory` from `PluginInput` is passed through for `client.session.prompt()` calls

**Tests** (`__tests__/index.test.ts`):
- Given valid config, when plugin is loaded, then it returns Hooks with `event` and `tool` keys
- Given a `session.created` event for a root session, when event handler fires, then `handleSessionCreated` is called
- Given a `session.created` event for a subtask (has parentID), when event handler fires, then `handleSessionCreated` is NOT called
- Given a `session.deleted` event, when event handler fires, then `handleSessionDeleted` is called
- Given the returned tools object, when inspected, then it contains viche_discover, viche_send, and viche_reply

**Commands**:
```bash
cd channel/opencode-plugin-viche && bun test __tests__/index.test.ts
cd channel/opencode-plugin-viche && bun test  # all tests
```

**Dependencies**: Phase 2 (config), Phase 3 (service), Phase 4 (tools)

**Must NOT do**:
- Register subtask sessions as Viche agents
- Load config per-session (load once at plugin init)
- Add shutdown/cleanup hooks beyond session.deleted (OpenCode doesn't expose plugin dispose)

**Pattern Reference**: Follow `@opencode-ai/plugin` example pattern and `channel/openclaw-plugin-viche/index.ts`

**TDD Gates**:
- RED: Write 5 failing tests for plugin integration
- GREEN: Implement index.ts to pass all tests
- VALIDATE: `bun test` — ALL tests pass (all phases)

---

### Phase 6: Skill, README, and Local Dev Wiring

**Files**:
- `.opencode/skills/viche/SKILL.md` — Create agent behavior instructions (NEW)
- `channel/opencode-plugin-viche/README.md` — Create setup documentation (NEW)
- `.opencode/plugins/viche.ts` — Create re-export for local dev (NEW)
- `.opencode/package.json` — Update to add local plugin dependency

**SKILL.md content** (model after existing skills in `.opencode/skills/`):

The skill should instruct the agent on:
1. **Inbound task handling**: When you receive `[Viche Task from {agentId}]`, execute the task and call `viche_reply` with your result
2. **Inbound result handling**: When you receive `[Viche Result from {agentId}]`, incorporate the result into your current work
3. **Discovery flow**: Use `viche_discover` to find agents with specific capabilities before sending
4. **Sending tasks**: Use `viche_send` to delegate work to other agents
5. **Protocol conventions**: Message types (task/result/ping), agent ID format (8-char hex)
6. **Error handling**: What to do if an agent is not found, if send fails, etc.

YAML frontmatter:
```yaml
---
name: viche
description: Viche agent network protocol. USE THIS when you need to communicate with other AI agents, delegate tasks, or respond to inbound messages from the Viche network.
---
```

**Local dev wiring** (`.opencode/plugins/viche.ts`):
```typescript
export { default } from "../../channel/opencode-plugin-viche/index.js";
```

**`.opencode/package.json` update**: Add the local plugin path or symlink.

**README.md content**:
- What the plugin does
- Prerequisites (Viche server running, OpenCode installed)
- Installation (local dev vs npm)
- Configuration (file + env vars with examples)
- Usage (loading the skill, using tools)
- Architecture overview (single-plugin, per-session agents)

**Tests**: No automated tests for this phase (documentation + config files).

**Commands**:
```bash
# Verify skill loads
# (manual: open OpenCode, type @skill viche, verify it loads)

# Verify plugin loads locally
# (manual: add "viche" to opencode.jsonc plugins array, restart OpenCode)

# Verify all tests still pass
cd channel/opencode-plugin-viche && bun test
```

**Dependencies**: Phase 5 (needs working plugin)

**Must NOT do**:
- Add the plugin to `opencode.jsonc` permanently (that's user choice)
- Create npm publish scripts
- Add CI/CD configuration
- Write E2E tests that require a running Viche server

**Pattern Reference**: Follow `.opencode/skills/beads/SKILL.md` for skill format, `channel/openclaw-plugin-viche/README.md` for README structure

---

## What We're NOT Doing

| Excluded Feature | Why | Future Consideration |
|-----------------|-----|---------------------|
| **npm publishing** | MVP is local-first; npm comes after validation | After E2E testing with real agents |
| **Multi-registry support** | Separate spec (private-registries) | `thoughts/tasks/private-registries/spec.md` |
| **Authentication** | Viche v1 has no auth; adding it here is premature | When Viche adds auth endpoints |
| **Message persistence** | Viche auto-consumes on read; plugin is fire-and-forget | If delivery guarantees needed |
| **Exactly-once delivery** | Acceptable message loss for v1 (per Oracle) | Acknowledgment flow in future |
| **Sidecar daemon** | Plugin system provides session awareness; sidecar is unnecessary | Only if cross-instance state needed |
| **Custom WebSocket reconnection** | Phoenix JS client handles reconnection | Only if reconnection proves unreliable |
| **Rate limiting / backpressure** | Low message volume expected in v1 | If agents start flooding |
| **Loop detection** | Ping-pong loops between agents | Add correlation IDs / source markers |
| **Per-subtask agents** | Subtasks share parent session's agent | If subtask isolation needed |

---

## Risks and Mitigations

| Risk | Trigger | Mitigation |
|------|---------|------------|
| Race condition: tool call before session ready | Fast tool call after session.created | `ensureSessionReady()` gate with in-flight dedup; tools wait for init |
| WebSocket URL mismatch | Different path than expected | Confirmed `/socket/websocket` from router.ex; test against running server |
| Phoenix JS client CJS/ESM issues | Import errors at runtime | Use `// @ts-ignore` like OpenClaw plugin; test import in isolation |
| Session.created event missing fields | OpenCode event shape changes | Defensive checks on `event.properties?.info?.id`; skip if missing |
| Inbound message injection fails | Session deleted mid-flight | Catch and log; don't crash (fire-and-forget) |
| Config file not found | First-time user | Graceful fallback to defaults; clear README instructions |
| Multiple OpenCode instances | Shared Viche registry | Each instance registers independently; agent IDs are unique |

---

## Success Criteria

### Verification Commands
```bash
# Run all plugin tests
cd channel/opencode-plugin-viche && bun test

# Type check
cd channel/opencode-plugin-viche && bun run tsc --noEmit

# Manual E2E (requires running Viche server)
# 1. Start Viche: iex -S mix phx.server
# 2. Start OpenCode with plugin loaded
# 3. In OpenCode session: call viche_discover with capability "*"
# 4. Register external agent via curl
# 5. Send message from external agent to OpenCode agent
# 6. Verify OpenCode receives and processes the message
```

### Final Checklist
- [ ] All "IN scope" items present
- [ ] All "OUT scope" items absent
- [ ] All tests pass (`bun test`)
- [ ] Type check passes (`tsc --noEmit`)
- [ ] Plugin loads in OpenCode without errors
- [ ] SKILL.md loads via `@skill viche`
- [ ] README.md has complete setup instructions
