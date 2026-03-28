# Spec 06: Channel Server (Claude Code MCP Integration)

> TypeScript MCP server for Claude Code. Depends on: all API specs (01-05) being deployed.

## Overview

`viche-channel.ts` is an MCP server that runs as a subprocess of Claude Code. It bridges the Viche registry with Claude Code's channel system: registers the agent on startup, polls the inbox for new messages, pushes them as channel notifications, and exposes a `viche_reply` tool so Claude can send results back.

> 📖 **Claude Code Channels reference:** https://code.claude.com/docs/en/channels-reference
> Channels are MCP servers over stdio that push events via `notifications/claude/channel`. Claude sees them as `<channel>` tags. Two-way channels expose tools so Claude can respond.

## Architecture

```
Claude Code (host process)
└── viche-channel.ts (MCP server over stdio)
    ├── On startup → POST /registry/register
    ├── Poll loop → GET /inbox/{agentId} every N seconds (auto-consumes)
    ├── On message → push notification via notifications/claude/channel
    └── viche_reply tool → POST /messages/{targetId}
```

## File Structure

```
channel/
├── viche-channel.ts    # MCP server entry point
├── package.json        # bun dependencies (@modelcontextprotocol/sdk)
└── .mcp.json.example   # example MCP config for users
```

## Configuration (Environment Variables)

| Variable | Default | Description |
|----------|---------|-------------|
| `VICHE_REGISTRY_URL` | `http://localhost:4000` | Viche registry base URL |
| `VICHE_AGENT_NAME` | `null` | Optional agent name for registration |
| `VICHE_CAPABILITIES` | `"coding"` | Comma-separated capabilities |
| `VICHE_DESCRIPTION` | `null` | Optional agent description |
| `VICHE_POLL_INTERVAL` | `"5"` | Poll interval in seconds |

## Startup Flow

1. Read env vars
2. POST to `{REGISTRY}/registry/register` with capabilities + optional name/description
3. Store returned `id` as `agentId`
4. Start poll loop
5. Log: "Viche: registered as {agentId}, polling every {N}s"

## Poll Loop

Every `VICHE_POLL_INTERVAL` seconds:

1. `GET {REGISTRY}/inbox/{agentId}` — this auto-consumes messages (Erlang receive semantics)
2. For each message in response:
   Push channel notification to Claude Code:
   ```json
   {
     "method": "notifications/claude/channel",
     "params": {
       "channel": "viche",
       "content": "[Task from {msg.from}] {msg.body}",
       "meta": { "message_id": "{msg.id}", "from": "{msg.from}" }
     }
   }
   ```

Since GET /inbox auto-consumes messages, there is **no duplicate message problem** — each poll returns only new messages that arrived since the last read. No local deduplication tracking needed.

## Tools Exposed

### viche_reply

Called by Claude after completing a task. Sends result back to the requesting agent.

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "to": {
      "type": "string",
      "description": "Agent ID to send the reply to (from the original message's 'from' field)"
    },
    "body": {
      "type": "string",
      "description": "Your result or response"
    }
  },
  "required": ["to", "body"]
}
```

**Tool behavior:**
1. `POST {REGISTRY}/messages/{to}` with `{"type": "result", "from": "{agentId}", "body": "{body}"}`
2. Return: `"Reply sent to {to}."`

> Note: No ack step needed. Messages were already consumed when the poll loop read the inbox. The reply is a simple new message send.

## MCP Config Example (.mcp.json)

```json
{
  "mcpServers": {
    "viche": {
      "command": "bun",
      "args": ["run", "./channel/viche-channel.ts"],
      "env": {
        "VICHE_REGISTRY_URL": "http://localhost:4000",
        "VICHE_CAPABILITIES": "coding,refactoring,testing",
        "VICHE_AGENT_NAME": "claude-code",
        "VICHE_DESCRIPTION": "Claude Code AI coding assistant"
      }
    }
  }
}
```

## Error Handling

- **Registry unreachable on startup** — retry 3 times with 2s backoff, then exit with error
- **Poll fails** — log warning, continue polling (transient network issues)
- **Reply fails** — return error text to Claude via tool response: `"Failed to send reply: {error}"`

## E2E Validation (V1: curl flow)

Before testing the channel, validate the full flow with curl:

```bash
VICHE=http://localhost:4000

# Register two agents (simulating channel + external agent)
CLAUDE=$(curl -s -X POST $VICHE/registry/register \
  -H 'Content-Type: application/json' \
  -d '{"name":"claude-code","capabilities":["coding"]}' | jq -r .id)

ARIS=$(curl -s -X POST $VICHE/registry/register \
  -H 'Content-Type: application/json' \
  -d '{"name":"aris","capabilities":["orchestration"]}' | jq -r .id)

# Aris discovers coding agent
curl -s "$VICHE/registry/discover?capability=coding" | jq

# Aris sends task to Claude
curl -s -X POST "$VICHE/messages/$CLAUDE" \
  -H 'Content-Type: application/json' \
  -d '{"type":"task","from":"'$ARIS'","body":"Implement rate limiter"}'

# Claude reads inbox (auto-consumed)
curl -s "$VICHE/inbox/$CLAUDE" | jq
# Expect: 1 task message from Aris

# Claude's inbox is now empty
curl -s "$VICHE/inbox/$CLAUDE" | jq
# Expect: {"messages": []}

# Claude sends result back to Aris
curl -s -X POST "$VICHE/messages/$ARIS" \
  -H 'Content-Type: application/json' \
  -d '{"type":"result","from":"'$CLAUDE'","body":"Done. 3 files changed."}'

# Aris reads inbox — should have result
curl -s "$VICHE/inbox/$ARIS" | jq
# Expect: result message from Claude
```

## E2E Validation (V2: channel integration)

1. Start Viche locally: `mix phx.server`
2. Place `channel/` directory in a test project
3. Add `.mcp.json` config pointing to localhost:4000
4. Start Claude Code
5. From another terminal, register an external agent and send a task to Claude's agent ID
6. Observe: Claude receives channel notification, processes task, calls `viche_reply`
7. Check external agent's inbox for the result

**Pass criteria:** Zero manual steps between sending task and receiving result.

## Test Plan

1. Unit: `viche-channel.ts` startup registers correctly
2. Unit: poll loop fetches and pushes notifications (no duplicates on consecutive polls)
3. Unit: `viche_reply` tool sends message to target agent
4. Integration: full round-trip curl flow (V1)
5. Integration: Claude Code channel flow (V2)

## Dependencies

- All Phoenix API endpoints (specs 01-04) must be deployed and functional
- `@modelcontextprotocol/sdk` npm package
- Bun runtime
