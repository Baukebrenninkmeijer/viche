---
date: 2026-03-24T12:00:00+02:00
researcher: mnemosyne
git_commit: cbefd3e68008f762d54057f5eb42614585d81d98
branch: main
repository: viche
topic: "OpenClaw (openclaw) project architecture and extension points for Viche integration"
scope: "/Users/ihorkatkov/Projects/openclaw"
query_type: map
tags: [research, openclaw, mcp, plugins, agent-communication]
status: complete
confidence: high
sources_scanned:
  files: 45
  thoughts_docs: 0
---

# Research: OpenClaw Architecture and Extension Points for Viche Integration

**Date**: 2026-03-24
**Commit**: cbefd3e68008f762d54057f5eb42614585d81d98
**Branch**: main
**Confidence**: high - extensive codebase review with clear documentation

## Query
Research the OpenCode (openclaw) project at `/Users/ihorkatkov/Projects/openclaw` to understand its architecture, extension/plugin system, and whether it has any channel-like mechanism similar to Claude Code's MCP channels.

## Summary
OpenClaw is a **TypeScript/Node.js personal AI assistant** with a Gateway-based architecture. It supports 20+ messaging channels (WhatsApp, Telegram, Discord, etc.), has a comprehensive plugin system, MCP server integration, and built-in agent-to-agent communication via `sessions_*` tools. The project has multiple integration points suitable for Viche: the plugin SDK, MCP server support, WebSocket Gateway protocol, and the existing session-based agent communication system.

## Key Entry Points

| File | Symbol | Purpose |
|------|--------|---------|
| `src/plugins/types.ts:1314` | `OpenClawPluginApi` | Main plugin registration API |
| `src/plugin-sdk/plugin-entry.ts:88` | `definePluginEntry` | Plugin entry point helper |
| `src/plugins/bundle-mcp.ts:322` | `loadEnabledBundleMcpConfig` | MCP server configuration loader |
| `src/gateway/server.impl.ts` | Gateway server | WebSocket control plane |
| `src/acp/types.ts` | ACP types | Agent Client Protocol integration |
| `docs/concepts/session-tool.md` | Session tools | Agent-to-agent communication |

## Architecture & Flow

### High-Level Architecture
```
Messaging Channels (WhatsApp/Telegram/Discord/etc.)
                │
                ▼
┌───────────────────────────────┐
│            Gateway            │
│       (control plane)         │
│     ws://127.0.0.1:18789      │
└──────────────┬────────────────┘
               │
               ├─ Pi agent (RPC) - LLM inference
               ├─ CLI (openclaw …)
               ├─ WebChat UI
               ├─ macOS/iOS/Android apps
               └─ Plugins (extensions/*)
```

### Plugin System Architecture
```
Plugin Entry (definePluginEntry)
        │
        ▼
OpenClawPluginApi
        │
        ├─ registerTool()        → Agent tools
        ├─ registerChannel()     → Messaging channels
        ├─ registerProvider()    → LLM providers
        ├─ registerService()     → Background services
        ├─ registerHook()        → Lifecycle hooks
        ├─ registerHttpRoute()   → HTTP endpoints
        ├─ registerGatewayMethod() → WebSocket methods
        └─ registerCommand()     → Chat commands
```

### MCP Integration
```
.mcp.json / claude.json / codex.json
        │
        ▼
loadEnabledBundleMcpConfig()
        │
        ▼
mcpServers: { serverName: { command, args, env, cwd } }
        │
        ▼
Stdio-based MCP server spawning
```

### Agent-to-Agent Communication (Built-in)
```
Session A                    Session B
    │                            │
    ├─ sessions_list ────────────┤
    ├─ sessions_history ─────────┤
    └─ sessions_send ───────────►│
                                 │
                    (message delivered with provenance)
```

## Related Components

### Plugin SDK Exports (`openclaw/plugin-sdk/*`)
- `plugin-entry` - Plugin definition helpers
- `core` - Channel plugin helpers
- `runtime` - Runtime utilities
- `acp-runtime` - ACP session management
- `gateway-runtime` - Gateway interaction
- `channel-runtime` - Channel utilities

### Key Directories
- `src/plugins/` - Plugin loader, registry, types
- `src/gateway/` - WebSocket server, methods, auth
- `src/acp/` - Agent Client Protocol integration
- `src/channels/` - Built-in messaging channels
- `extensions/` - Plugin packages (83 extensions)

### Configuration
- Main config: `~/.openclaw/openclaw.json`
- Plugin config: `openclaw.plugin.json` per extension
- MCP config: `.mcp.json` (Claude-compatible)

## Configuration & Runtime

### Environment Variables
- `OPENCLAW_API_KEY` - API key for OpenCode Zen
- Various channel tokens (TELEGRAM_BOT_TOKEN, DISCORD_BOT_TOKEN, etc.)

### Config Schema (from `src/plugins/types.ts`)
```typescript
type OpenClawPluginApi = {
  id: string;
  name: string;
  config: OpenClawConfig;
  pluginConfig?: Record<string, unknown>;
  runtime: PluginRuntime;
  registerTool: (tool, opts?) => void;
  registerChannel: (registration) => void;
  registerProvider: (provider) => void;
  registerService: (service) => void;
  registerHook: (events, handler, opts?) => void;
  registerHttpRoute: (params) => void;
  registerGatewayMethod: (method, handler) => void;
  registerCommand: (command) => void;
  // ... more
};
```

### Session Tools Configuration
```json
{
  "session": {
    "sendPolicy": {
      "rules": [
        { "match": { "channel": "discord", "chatType": "group" }, "action": "deny" }
      ],
      "default": "allow"
    }
  }
}
```

## Historical Context

No prior research found in thoughts/ directory for this external project.

## Gaps Identified

| Gap | Search Terms Used | Directories Searched |
|-----|-------------------|---------------------|
| No Viche-specific integration | "viche", "registry" | `extensions/`, `src/` |
| No external agent discovery | "discover", "capability" | `src/plugins/`, `src/gateway/` |
| MCP channels not supported | "channel", "mcp" | `src/plugins/bundle-mcp.ts` |
| No WebSocket client for external registries | "websocket client", "external" | `src/gateway/` |

**Key Gap**: OpenClaw's MCP integration only supports **stdio-based MCP servers** (command + args). It does not support MCP channels (the bidirectional notification mechanism used by Claude Code). The `bundle-mcp.ts` explicitly checks for `command` field and marks servers without it as "unsupported".

## Evidence Index

### Code Files
- `package.json:1-881` - Project metadata, dependencies including `@modelcontextprotocol/sdk`
- `README.md:1-516` - Project overview, architecture diagram
- `AGENTS.md:1-215` - Development guidelines
- `src/plugins/types.ts:1300-1450` - Plugin API types
- `src/plugin-sdk/plugin-entry.ts:1-104` - Plugin entry helper
- `src/plugins/bundle-mcp.ts:1-360` - MCP server loading
- `docs/concepts/session-tool.md:1-200` - Session tools documentation
- `src/acp/types.ts:1-51` - ACP types
- `extensions/acpx/index.ts:1-19` - ACPX plugin entry

### External Documentation
- https://docs.openclaw.ai - Official documentation
- https://docs.openclaw.ai/concepts/session-tool - Session tools reference

## Related Research

- `thoughts/research/2026-03-24-e2e-message-passing-claude-code.md` - Claude Code MCP channel pattern (for comparison)

---

## Handoff Inputs

**If planning needed** (for @prometheus):
- Scope: OpenClaw plugin system, Gateway WebSocket protocol, session tools
- Entry points: `src/plugin-sdk/plugin-entry.ts`, `src/plugins/types.ts`
- Constraints found:
  - MCP integration is stdio-only (no channel support)
  - Plugin system is TypeScript/Node.js
  - Gateway uses WebSocket at `ws://127.0.0.1:18789`
  - Built-in agent-to-agent via `sessions_send` tool
- Open questions:
  - Should Viche integration be a plugin or external service?
  - Should it use Gateway WebSocket or HTTP endpoints?
  - Should it extend `sessions_*` tools or create new tools?

**If implementation needed** (for @vulkanus):
- Test location: Colocated `*.test.ts` files
- Pattern to follow: `extensions/*/index.ts` with `definePluginEntry`
- Entry point: `src/plugin-sdk/plugin-entry.ts`

## Key Findings Summary

1. **OpenClaw is TypeScript/Node.js** (not Go) - a personal AI assistant with Gateway architecture
2. **Has MCP server support** via `.mcp.json` but **only stdio transport** (no MCP channels)
3. **Rich plugin system** with `definePluginEntry()` for tools, channels, providers, services
4. **Built-in agent-to-agent communication** via `sessions_list`, `sessions_history`, `sessions_send` tools
5. **WebSocket Gateway** at `ws://127.0.0.1:18789` for control plane
6. **ACP (Agent Client Protocol)** integration for external agent runtimes
7. **No external agent discovery** - sessions are local to the Gateway instance

## Integration Options for Viche

### Option A: OpenClaw Plugin
Create an OpenClaw plugin that:
- Registers with Viche on Gateway startup
- Exposes capabilities based on enabled tools/channels
- Adds `viche_discover`, `viche_send` tools
- Receives messages via WebSocket from Viche

### Option B: Gateway WebSocket Client
Create a Viche channel that:
- Connects to OpenClaw Gateway WebSocket
- Uses existing `sessions_send` for message delivery
- Bridges Viche messages to OpenClaw sessions

### Option C: HTTP Bridge
Create a Viche-to-OpenClaw HTTP bridge that:
- Uses OpenClaw's HTTP endpoints (`/sessions/{key}/history`, etc.)
- Registers OpenClaw instances as Viche agents
- Translates between Viche messages and OpenClaw sessions
