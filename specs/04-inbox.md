# Spec 04: Inbox (Read & Consume)

> Read and auto-consume messages. Depends on: [01-agent-lifecycle](./01-agent-lifecycle.md), [03-messaging](./03-messaging.md)

## Overview

Agents read their inbox to get pending messages. **Reading consumes messages** — like Erlang's `receive`, GET /inbox returns all pending messages and removes them from the inbox in one atomic operation. There is no separate ack endpoint.

This is the purest actor model semantics: messages sit in the mailbox until the agent reads them, then they're gone.

## API Contract

### GET /inbox/{agentId}

Returns all pending messages (oldest-first) and **removes them from the inbox**. Subsequent calls return only new messages that arrived after the read.

**Response 200:**
```json
{
  "messages": [
    {
      "id": "msg-a1b2c3d4",
      "type": "task",
      "from": "sender-id",
      "body": "Implement rate limiter...",
      "sent_at": "2026-03-24T10:01:00Z"
    }
  ]
}
```

**Response 200 (empty inbox / no new messages):**
```json
{
  "messages": []
}
```

**Response 404 (agent not found):**
```json
{
  "error": "agent_not_found"
}
```

## Flow

1. Controller receives GET /inbox/{agentId}
2. Looks up agent GenServer via Registry
3. If not found → 404
4. Calls `GenServer.call(agent_pid, :drain_inbox)`
5. GenServer returns its inbox list AND resets inbox to `[]` (atomic operation)
6. Returns 200 with messages

## GenServer Implementation

The key operation is atomic drain — return current inbox and reset in one call:

```elixir
def handle_call(:drain_inbox, _from, %{inbox: inbox} = state) do
  {:reply, inbox, %{state | inbox: []}}
end
```

This ensures no race conditions: a message arriving between the read and a hypothetical separate "clear" would not be lost.

## Reply Pattern (Convention, Not Enforced)

To "reply" to a message, the agent reads the `from` field and sends a new message:

```bash
# Agent B reads inbox (messages are consumed)
MSGS=$(curl -s "http://localhost:4000/inbox/$B")

# Agent B extracts the sender from a message and sends result back
FROM=$(echo $MSGS | jq -r '.messages[0].from')
curl -s -X POST "http://localhost:4000/messages/$FROM" \
  -H 'Content-Type: application/json' \
  -d '{"type":"result","from":"'$B'","body":"Task completed. 3 files changed."}'
```

## Acceptance Criteria

```bash
# Setup
A=$(curl -s -X POST http://localhost:4000/registry/register \
  -H 'Content-Type: application/json' \
  -d '{"capabilities":["testing"]}' | jq -r .id)

B=$(curl -s -X POST http://localhost:4000/registry/register \
  -H 'Content-Type: application/json' \
  -d '{"capabilities":["coding"]}' | jq -r .id)

# Send message A → B
curl -s -X POST "http://localhost:4000/messages/$B" \
  -H 'Content-Type: application/json' \
  -d '{"type":"task","from":"'$A'","body":"do the thing"}'

# Read B's inbox — should have 1 message
curl -s "http://localhost:4000/inbox/$B" | jq
# Expect: 1 message from A

# Read B's inbox again — should be empty (consumed on first read)
curl -s "http://localhost:4000/inbox/$B" | jq
# Expect: {"messages": []}

# Send another message, then read — proves new messages still arrive
curl -s -X POST "http://localhost:4000/messages/$B" \
  -H 'Content-Type: application/json' \
  -d '{"type":"task","from":"'$A'","body":"second task"}'
curl -s "http://localhost:4000/inbox/$B" | jq
# Expect: 1 message ("second task")

# Full reply flow
curl -s -X POST "http://localhost:4000/messages/$A" \
  -H 'Content-Type: application/json' \
  -d '{"type":"result","from":"'$B'","body":"done"}'
curl -s "http://localhost:4000/inbox/$A" | jq
# Expect: result message from B

# Non-existent agent → 404
curl -s "http://localhost:4000/inbox/nonexistent" | jq
# Expect: 404
```

## Test Plan

1. Read empty inbox — returns empty list
2. Read inbox with messages — returns oldest-first, inbox cleared
3. Second read after consume — returns empty list
4. Messages arriving after read — appear on next read
5. Concurrent sends during read — no messages lost (GenServer serialization)
6. Full round-trip: send → read (auto-consume) → reply → read
7. Non-existent agent — 404

## Dependencies

- [01-agent-lifecycle](./01-agent-lifecycle.md) — agent GenServer must exist
- [03-messaging](./03-messaging.md) — messages must be sendable to test inbox
