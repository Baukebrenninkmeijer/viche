---
date: 2026-03-24T12:00:00+02:00
researcher: mnemosyne
topic: "OpenClaw ↔ Viche Integration"
scope: "OpenClaw plugin integration with Viche agent network"
query_type: map
tags: [research, openclaw, viche, integration, multi-agent]
status: complete
confidence: high
sources_scanned:
  files: 1
  thoughts_docs: 0
---

# OpenClaw ↔ Viche Integration Research

## Problem Statement

OpenClaw instances on different machines/networks can't discover or message each other. The current limitations are:

- **Local-only inter-agent tools**: OpenClaw's built-in inter-agent tools (`sessions_list`, `sessions_history`, `sessions_send`, `sessions_spawn`) are LOCAL to one gateway instance only
- **LAN-only discovery**: OpenClaw's discovery is Bonjour/mDNS on LAN only (`_openclaw-gw._tcp`), no cross-network agent discovery
- **No cross-network messaging**: Agents on different OpenClaw gateways cannot communicate

Viche provides the missing layer: registration, capability-based discovery, and async messaging infrastructure.

**Goal**: OpenClaw-A discovers OpenClaw-B by capability, sends a task, receives a result.

## Integration Approaches

### Option A: OpenClaw Plugin (RECOMMENDED)

Create an OpenClaw plugin `openclaw-plugin-viche` using `definePluginEntry()`.

**Components**:

- `api.registerService()` — background service that:
  - On gateway startup: POST `/registry/register` to Viche → gets `agent_id`
  - Connects WebSocket to Viche Phoenix Channel `agent:{agent_id}`
  - Listens for `new_message` events
  - On inbound message: calls OpenClaw's internal session injection (like `sessions_send` or `prompt_async` equivalent)

- `api.registerTool()` — three tools:
  - `viche_discover` — HTTP GET to Viche `/registry/discover?capability=X`
  - `viche_send` — HTTP POST to Viche `/messages/{to}` with `{from: agent_id, body, type}`
  - `viche_reply` — same as send but with `type: "result"`

- `api.registerHttpRoute()` — optional health/status endpoint

- Plugin config schema: `{ registryUrl, capabilities, agentName, description }`

**Pros**:
- Native integration with OpenClaw
- Full lifecycle management (starts/stops with gateway)
- Tools available to all agents/sessions
- Single process (no sidecar needed)
- Proper error handling and logging through OpenClaw's infrastructure

**Cons**:
- Requires OpenClaw plugin development knowledge
- Must publish to ClawHub/npm
- Tied to OpenClaw's plugin API stability

### Option B: Webhook Bridge (Sidecar)

Standalone TypeScript/Bun daemon that acts as a bridge between Viche and OpenClaw.

**Architecture**:
- Registers with Viche on startup
- Connects WebSocket to Viche
- On inbound Viche message → POST `/hooks/agent` to OpenClaw with `{ message: "[Viche Task from {from}] {body}", agentId: "viche" }`
- OpenClaw agent uses MCP tools (stdio MCP server, like Claude pattern) to discover/send/reply

**Pros**:
- No plugin development needed
- Works with any OpenClaw version
- Simple deployment (just run the daemon)
- Can be updated independently of OpenClaw

**Cons**:
- Two processes to manage (sidecar + gateway)
- Webhook auth setup required
- Less integrated (feels like external service)
- Additional failure point

### Option C: MCP Server Only (Minimal)

Just a stdio MCP server in OpenClaw's config.

**Components**:
- Provides `viche_discover`, `viche_send`, `viche_reply` tools via HTTP to Viche REST API
- NO real-time inbound messages (no WebSocket, no push)
- Inbound would require polling the inbox endpoint

**Pros**:
- Simplest to build
- Works today with existing OpenClaw
- No lifecycle management needed
- Minimal dependencies

**Cons**:
- No real-time push (no WebSocket, no inbound messages)
- Polling is wasteful and has latency
- No lifecycle management (registration/deregistration)
- Poor user experience for async workflows

## Recommended Architecture (Option A - Plugin)

```
┌─ OpenClaw Gateway ────────────────────────────────────┐
│                                                        │
│  Plugin: openclaw-plugin-viche                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Service (background):                            │  │
│  │   • Registers agent with Viche on startup        │  │
│  │   • WebSocket → Phoenix Channel agent:{id}       │  │
│  │   • new_message → inject into target session     │  │
│  │                                                  │  │
│  │ Tools:                                           │  │
│  │   • viche_discover(capability) → agent list      │  │
│  │   • viche_send(to, body, type) → sends message   │  │
│  │   • viche_reply(to, body) → sends result         │  │
│  └──────────────────────────────────────────────────┘  │
│                                                        │
│  Agent "main"        Agent "coding"                    │
│  ┌──────────┐        ┌──────────┐                      │
│  │ Can call │        │ Can call │                      │
│  │ viche_*  │        │ viche_*  │                      │
│  │ tools    │        │ tools    │                      │
│  └──────────┘        └──────────┘                      │
└────────────────────────┬───────────────────────────────┘
                         │
                         │ HTTP + WebSocket
                         ▼
              ┌──────────────────────┐
              │  Viche Registry       │
              │  (Phoenix, :4000)     │
              │                      │
              │  • /registry/register │
              │  • /registry/discover │
              │  • /messages/{id}     │
              │  • /agent/websocket   │
              └──────────────────────┘
                         ▲
                         │
              ┌──────────────────────┐
              │  Other OpenClaw /     │
              │  Claude Code /        │
              │  Any Agent            │
              └──────────────────────┘
```

## Message Flow (E2E)

1. **OpenClaw-A starts** → plugin registers with Viche → agent_id = "a1b2c3d4", capabilities: ["coding"]
2. **OpenClaw-B starts** → plugin registers with Viche → agent_id = "e5f6g7h8", capabilities: ["research"]
3. **OpenClaw-B's LLM calls** `viche_discover("coding")` → finds OpenClaw-A
4. **OpenClaw-B calls** `viche_send(to: "a1b2c3d4", body: "Review this PR", type: "task")`
5. **Viche delivers** via WebSocket to OpenClaw-A's plugin service
6. **Plugin injects message** into OpenClaw-A's session: "[Viche Task from e5f6g7h8] Review this PR"
7. **OpenClaw-A processes**, calls `viche_reply(to: "e5f6g7h8", body: "PR looks good, 2 issues found")`
8. **Viche delivers result** to OpenClaw-B

## Plugin Skeleton Code

```typescript
// openclaw-plugin-viche/index.ts
import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import { Type } from "@sinclair/typebox";

export default definePluginEntry({
  id: "viche",
  name: "Viche Agent Network",
  description: "Discover and message AI agents across the Viche network",
  configSchema: Type.Object({
    registryUrl: Type.String({ default: "http://localhost:4000" }),
    capabilities: Type.Array(Type.String(), { default: ["coding"] }),
    agentName: Type.Optional(Type.String()),
    description: Type.Optional(Type.String()),
  }),
  register(api) {
    const config = api.pluginConfig as {
      registryUrl: string;
      capabilities: string[];
      agentName?: string;
      description?: string;
    };
    let agentId: string | null = null;

    // Background service: registration + WebSocket
    api.registerService({
      name: "viche-bridge",
      async start() {
        // 1. Register with Viche
        const resp = await fetch(`${config.registryUrl}/registry/register`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            capabilities: config.capabilities,
            name: config.agentName,
            description: config.description,
          }),
        });
        const data = await resp.json();
        agentId = data.id;

        // 2. Connect WebSocket (Phoenix Channel)
        // ... phoenix channel connection code ...
        // 3. On new_message → inject into session
      },
      async stop() {
        // Cleanup: close WebSocket
      },
    });

    // Tool: discover agents
    api.registerTool({
      name: "viche_discover",
      description: "Discover AI agents on the Viche network by capability",
      parameters: Type.Object({
        capability: Type.String({ description: "Capability to search for" }),
      }),
      async execute(_id, params) {
        const resp = await fetch(
          `${config.registryUrl}/registry/discover?capability=${params.capability}`
        );
        const data = await resp.json();
        return { content: [{ type: "text", text: formatAgents(data.agents) }] };
      },
    });

    // Tool: send message
    api.registerTool({
      name: "viche_send",
      description: "Send a message to another AI agent on the Viche network",
      parameters: Type.Object({
        to: Type.String({ description: "Target agent ID" }),
        body: Type.String({ description: "Message content" }),
        type: Type.Optional(Type.String({ description: "task | result | ping", default: "task" })),
      }),
      async execute(_id, params) {
        await fetch(`${config.registryUrl}/messages/${params.to}`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            from: agentId,
            body: params.body,
            type: params.type ?? "task",
          }),
        });
        return { content: [{ type: "text", text: `Sent to ${params.to}` }] };
      },
    });

    // Tool: reply
    api.registerTool({
      name: "viche_reply",
      description: "Reply to an agent that sent you a task",
      parameters: Type.Object({
        to: Type.String({ description: "Agent ID to reply to" }),
        body: Type.String({ description: "Your result" }),
      }),
      async execute(_id, params) {
        await fetch(`${config.registryUrl}/messages/${params.to}`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            from: agentId,
            body: params.body,
            type: "result",
          }),
        });
        return { content: [{ type: "text", text: `Reply sent to ${params.to}` }] };
      },
    });
  },
});
```

## Comparison Table

| Aspect | Claude Code (Reference) | OpenClaw Plugin | OpenClaw Webhook Bridge |
|--------|------------------------|-----------------|------------------------|
| Integration type | MCP Channel (stdio) | Native Plugin | Sidecar + MCP server |
| Registration | MCP server on startup | Plugin service on startup | Sidecar on startup |
| Inbound messages | `notifications/claude/channel` | Session injection via plugin API | `POST /hooks/agent` |
| Tools | MCP tools (3) | Plugin tools (3) | MCP tools (3) |
| WebSocket owner | MCP server process | Plugin service | Sidecar daemon |
| Agent identity | Implicit (1 process = 1 agent) | Plugin-managed (can be per-agent) | Sidecar-managed |
| Lifecycle | Dies with Claude session | Lives with Gateway | Independent daemon |
| Real-time push | Yes (channel notification) | Yes (session injection) | Yes (webhook) |
| Processes | 1 | 0 (part of gateway) | 2 (sidecar + MCP) |

## Open Questions

1. **Multi-agent per gateway**: Should each OpenClaw agent get its own Viche agent_id? (Probably yes — plugin can iterate `agents.list` and register each)
2. **Session injection method**: What's the best way to inject inbound messages? Options: `sessions_send` tool internally, or direct session store write, or webhook to self
3. **Phoenix client in Node.js**: The `phoenix` npm package works for WebSocket. Need to verify compatibility with OpenClaw's Node.js runtime (not Bun)
4. **Plugin distribution**: Publish to ClawHub or npm? ClawHub is preferred for OpenClaw ecosystem
5. **Config schema**: Should use TypeBox (OpenClaw's standard) for config validation

## Next Steps

1. Validate plugin approach by reading OpenClaw plugin examples (check their GitHub)
2. Prototype the minimal plugin with just `viche_discover` tool
3. Add WebSocket service for inbound messages
4. Test cross-gateway messaging between two OpenClaw instances

## Evidence Index

Reference:
- `channel/viche-channel.ts` — Claude Code MCP Channel implementation (reference pattern)
- OpenClaw docs at docs.openclaw.ai — Plugin system, webhooks, multi-agent architecture

## Related Research

- `thoughts/research/2026-03-24-openclaw-architecture.md` — OpenClaw architecture details
- `thoughts/research/2026-03-24-viche-mcp-channel-integration.md` — Viche MCP channel integration
