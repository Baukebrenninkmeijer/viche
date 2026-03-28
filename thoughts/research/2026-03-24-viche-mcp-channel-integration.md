---
date: 2026-03-24T12:00:00+02:00
researcher: mnemosyne
git_commit: HEAD
branch: main
repository: viche
topic: "Viche MCP Channel integration pattern for Claude Code"
scope: channel/ directory, specs 01-10
query_type: explain
tags: [research, mcp, channel, claude-code, websocket, phoenix]
status: complete
confidence: high
sources_scanned:
  files: 14
  thoughts_docs: 3
---

# Research: Viche MCP Channel Integration Pattern

**Date**: 2026-03-24
**Commit**: HEAD
**Branch**: main
**Confidence**: high — full implementation and specs available

## Query
Research and document the Viche MCP Channel integration pattern — how Claude Code was integrated with Viche for agent-to-agent communication.

## Summary

The Viche MCP Channel is a TypeScript MCP server (`viche-channel.ts`) that bridges Claude Code with the Viche agent registry. It uses the MCP SDK's `Server` class with `StdioServerTransport` for stdio communication with Claude Code, registers as an agent via HTTP on startup, connects to Viche's Phoenix Channel via WebSocket for real-time message delivery, and exposes three tools (`viche_discover`, `viche_send`, `viche_reply`) for agent interaction. The key differentiator making this a "channel" (vs a regular MCP server) is the `experimental: { "claude/channel": {} }` capability and the use of `notifications/claude/channel` to push inbound messages to Claude Code as `<channel source="viche">` tags.

## Key Entry Points

| File | Symbol | Purpose |
|------|--------|---------|
| `channel/viche-channel.ts:1-6` | imports | MCP SDK Server, StdioServerTransport, request schemas |
| `channel/viche-channel.ts:8` | `Socket` | Phoenix WebSocket client from `phoenix` npm package |
| `channel/viche-channel.ts:178-192` | `main()` → `new Server()` | MCP server instantiation with channel capabilities |
| `channel/viche-channel.ts:117-156` | `connectWebSocket()` | Phoenix Channel connection and message listener |
| `channel/viche-channel.ts:126-140` | `channel.on("new_message", ...)` | Inbound message handler → MCP notification |

## Architecture & Flow

### Process Model

```
Claude Code (host process, interactive mode)
└── viche-channel.ts (MCP server over stdio)
    ├── On startup → POST /registry/register via HTTP
    ├── On startup → Connect WebSocket to /agent/websocket
    ├── Join Phoenix Channel "agent:{agentId}"
    ├── On "new_message" event → push MCP notification to Claude Code
    └── Tools: viche_discover, viche_send, viche_reply → push events via WebSocket
```

### Startup Sequence

1. **MCP Server instantiation** (`channel/viche-channel.ts:179-192`)
   - Creates `Server` with name `"viche-channel"`, version `"0.2.0"`
   - Declares capabilities: `{ experimental: { "claude/channel": {} }, tools: {} }`
   - Sets instructions for Claude: tasks arrive as `<channel source="viche">` tags

2. **Agent registration** (`channel/viche-channel.ts:45-90`)
   - POST to `{REGISTRY_URL}/registry/register` with capabilities, optional name/description
   - Retry logic: 3 attempts with 2s backoff
   - Returns server-assigned 8-char hex `agentId`

3. **Stdio transport connection** (`channel/viche-channel.ts:350-351`)
   - `new StdioServerTransport()` → `server.connect(transport)`
   - Establishes bidirectional JSON-RPC over stdin/stdout with Claude Code

4. **WebSocket connection** (`channel/viche-channel.ts:117-156`)
   - Derives WebSocket URL: `http://...` → `ws://.../agent/websocket`
   - Creates Phoenix `Socket` with `{ params: { agent_id: agentId } }`
   - Joins channel `agent:{agentId}`
   - Registers `new_message` event handler

### Data Flow: Inbound Message (Viche → Claude Code)

```
External Agent
    │
    ▼ POST /messages/{agentId}
Viche Server (Phoenix)
    │
    ▼ VicheWeb.Endpoint.broadcast("agent:{agentId}", "new_message", payload)
Phoenix Channel (WebSocket)
    │
    ▼ channel.on("new_message", callback)
viche-channel.ts
    │
    ▼ server.notification({ method: "notifications/claude/channel", params: {...} })
Claude Code
    │
    ▼ Renders as <channel source="viche">[Task from {from}] {body}</channel>
```

**Implementation** (`channel/viche-channel.ts:126-140`):
```typescript
channel.on("new_message", (payload: { id: string; from: string; body: string }) => {
  server.notification({
    method: "notifications/claude/channel",
    params: {
      channel: "viche",
      content: `[Task from ${payload.from}] ${payload.body}`,
      meta: { message_id: payload.id, from: payload.from },
    },
  });
});
```

### Data Flow: Outbound Message (Claude Code → Viche)

```
Claude Code
    │
    ▼ Calls viche_send or viche_reply tool
viche-channel.ts (CallToolRequestSchema handler)
    │
    ▼ channelPush(activeChannel, "send_message", { to, body, type })
Phoenix Channel (WebSocket)
    │
    ▼ VicheWeb.AgentChannel handles "send_message" event
Viche Server
    │
    ▼ Delivers to target agent's inbox + broadcasts to their WebSocket
```

## MCP SDK Integration Points

### Server Instantiation (`channel/viche-channel.ts:179-192`)

```typescript
const server = new Server(
  { name: "viche-channel", version: "0.2.0" },
  {
    capabilities: {
      experimental: { "claude/channel": {} },  // ← KEY: declares this is a channel
      tools: {},
    },
    instructions: 'Viche channel: tasks from other AI agents arrive as <channel source="viche"> tags...',
  }
);
```

### Transport (`channel/viche-channel.ts:350-351`)

```typescript
const transport = new StdioServerTransport();
await server.connect(transport);
```

### Request Handlers

| Schema | Handler Location | Purpose |
|--------|------------------|---------|
| `ListToolsRequestSchema` | `channel/viche-channel.ts:198-262` | Returns tool definitions for discover/send/reply |
| `CallToolRequestSchema` | `channel/viche-channel.ts:265-347` | Executes tool calls via Phoenix Channel |

### Notification Method

The `notifications/claude/channel` method is the MCP protocol mechanism for pushing channel content to Claude Code:

```typescript
server.notification({
  method: "notifications/claude/channel",
  params: {
    channel: "viche",           // Channel identifier
    content: "...",             // Text content shown to Claude
    meta: { ... },              // Metadata (message_id, from)
  },
});
```

## What Makes This a "Channel" vs Regular MCP Server

| Aspect | Regular MCP Server | MCP Channel (Viche) |
|--------|-------------------|---------------------|
| Capability declaration | `{ tools: {} }` | `{ experimental: { "claude/channel": {} }, tools: {} }` |
| Notification method | N/A | `notifications/claude/channel` |
| Claude Code rendering | Tool results only | `<channel source="viche">` tags for pushed content |
| Push capability | None (request-response only) | Server can push notifications asynchronously |
| Startup flag | `--mcp-server` | `--dangerously-load-development-channels server:viche` |
| Instructions | Optional | Describes how Claude should handle channel content |

**Key insight**: The `experimental: { "claude/channel": {} }` capability tells Claude Code this MCP server can push asynchronous notifications. Without this capability, the server would be request-response only.

## Tools Exposed

### viche_discover (`channel/viche-channel.ts:200-215`, `279-295`)

- **Input**: `{ capability: string }`
- **Behavior**: Pushes `"discover"` event to Phoenix Channel, awaits reply
- **Output**: Formatted agent list or "No agents found"

### viche_send (`channel/viche-channel.ts:216-240`, `298-325`)

- **Input**: `{ to: string, body: string, type?: "task"|"result"|"ping" }`
- **Behavior**: Pushes `"send_message"` event to Phoenix Channel
- **Output**: Confirmation text

### viche_reply (`channel/viche-channel.ts:241-261`, `327-344`)

- **Input**: `{ to: string, body: string }`
- **Behavior**: Pushes `"send_message"` event with `type: "result"`
- **Output**: Confirmation text

## Configuration

| Variable | Default | Location |
|----------|---------|----------|
| `VICHE_REGISTRY_URL` | `http://localhost:4000` | `channel/viche-channel.ts:12-13` |
| `VICHE_AGENT_NAME` | `null` | `channel/viche-channel.ts:14` |
| `VICHE_CAPABILITIES` | `"coding"` | `channel/viche-channel.ts:15-18` |
| `VICHE_DESCRIPTION` | `null` | `channel/viche-channel.ts:19` |

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `@modelcontextprotocol/sdk` | `^1.0.0` | MCP Server, StdioServerTransport, request schemas |
| `phoenix` | `^1.7.0` | WebSocket client for Phoenix Channels |

Runtime: **Bun** (TypeScript execution)

## Spec Files and Coverage

| Spec | File | Coverage |
|------|------|----------|
| 01-agent-lifecycle | `specs/01-agent-lifecycle.md` | Agent struct, registration API, GenServer architecture |
| 02-discovery | `specs/02-discovery.md` | GET /registry/discover endpoint |
| 03-messaging | `specs/03-messaging.md` | POST /messages/{agentId}, message types, broadcast flow |
| 04-inbox | `specs/04-inbox.md` | GET /inbox/{agentId}, auto-consume semantics |
| 05-well-known | `specs/05-well-known.md` | /.well-known/agent-registry for self-onboarding |
| 06-channel-server | `specs/06-channel-server.md` | **Primary spec for viche-channel.ts** — full architecture, tools, MCP config |
| 07-websockets | `specs/07-websockets.md` | Phoenix Channel events, AgentSocket, AgentChannel |
| 08-auto-deregister | `specs/08-auto-deregister.md` | WebSocket disconnect grace period, polling timeout |
| 09-observe-monitor | `specs/09-observe-monitor.md` | Future: registry event subscriptions (not implemented) |
| 10-opencode-bridge | `specs/10-opencode-bridge.md` | Alternative pattern for OpenCode (two-component: MCP + sidecar) |

## Gaps Identified

| Gap | Search Terms Used | Notes |
|-----|-------------------|-------|
| No test files for channel | `viche-channel.test`, `channel/*.test.ts` | Spec 06 lists test plan but no implementation found |
| No reconnection logic | `reconnect`, `backoff` in channel code | WebSocket disconnect exits process; no auto-reconnect |
| No deregistration on shutdown | `deregister`, `cleanup`, `SIGTERM` | Process exits without explicit deregistration (relies on Spec 08 auto-deregister) |

## Evidence Index

### Code Files
- `channel/viche-channel.ts:1-361` — Full MCP channel implementation
- `channel/package.json:1-13` — Dependencies and scripts
- `channel/.mcp.json.example:1-14` — Example MCP configuration

### Specification Files
- `specs/06-channel-server.md:1-372` — Primary spec for channel integration
- `specs/07-websockets.md:1-226` — WebSocket/Phoenix Channel protocol
- `specs/10-opencode-bridge.md:1-533` — Comparison with OpenCode pattern

### Documentation
- Claude Code Channels reference: https://code.claude.com/docs/en/channels-reference

## Related Research

- `thoughts/research/2026-03-24-e2e-message-passing-claude-code.md` — E2E testing of message flow
- `thoughts/research/2026-03-24-agent-lifecycle.md` — Agent registration/deregistration

---

## Handoff Inputs

**If adapting for OpenCode** (for @prometheus or @vulkanus):
- Scope: MCP server + sidecar bridge (two components required per Spec 10)
- Key difference: OpenCode MCP servers are instance-scoped, not session-scoped
- Entry points: `specs/10-opencode-bridge.md` for full architecture
- Pattern to follow: `channel/viche-channel.ts` for MCP SDK usage, but split into stateless tools + sidecar

**If implementing for another AI tool**:
- Required MCP SDK components: `Server`, `StdioServerTransport`, `ListToolsRequestSchema`, `CallToolRequestSchema`
- Channel capability: `{ experimental: { "claude/channel": {} } }` (Claude-specific; other tools may differ)
- Notification method: `notifications/claude/channel` (Claude-specific)
- WebSocket client: `phoenix` npm package for Phoenix Channel protocol
