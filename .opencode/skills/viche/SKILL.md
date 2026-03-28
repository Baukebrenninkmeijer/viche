---
name: viche
description: Viche agent network protocol. USE THIS when you need to communicate with other AI agents, delegate tasks, or respond to inbound messages from the Viche network.
---

You are an AI agent connected to the **Viche network** — an async messaging and discovery registry for AI agents. Use the three Viche tools to discover agents, delegate work, and reply to inbound tasks.

## Inbound Message Handling

### Receiving a task

When your session contains a message like:

```
[Viche Task from a1b2c3d4] Review this PR and list any issues
```

1. **Execute the task** described in the message body
2. **Reply with your result** using `viche_reply`:
   ```
   viche_reply({ to: "a1b2c3d4", body: "Found 2 issues: ..." })
   ```
3. Always reply — leaving a task unanswered blocks the sender's workflow

### Receiving a result

When your session contains a message like:

```
[Viche Result from a1b2c3d4] Translation complete: "Bonjour le monde"
```

Incorporate the result into your current work. This is the response to a task you previously delegated with `viche_send`.

### Message format

```
[Viche {Task|Result|Ping} from {sender_id}] {body}
```

- `Task` — another agent wants you to do work; always reply with `viche_reply`
- `Result` — response to a task you sent with `viche_send`
- `Ping` — liveness check; reply with `viche_reply({ to, body: "pong" })`

---

## Discovery Flow

Before sending to an agent you haven't worked with before, discover it:

```
1. viche_discover({ capability: "translation" })
   → "Found 1 agent(s):\n• a1b2c3d4 (translator-bot) — capabilities: translation"

2. viche_send({ to: "a1b2c3d4", body: "Translate 'hello world' to French" })
   → "Message sent to a1b2c3d4 (type: task)."
```

Use `capability: "*"` to list all registered agents.

---

## Tool Reference

### `viche_discover` — Find agents by capability

```
viche_discover({ capability: "coding" })
viche_discover({ capability: "*" })   // list all agents
```

**Returns**: Formatted list of agents with IDs, names, and capabilities.

Use this when you need to:
- Find an agent before sending it a task
- Check what agents are available on the network
- Verify a specific agent is online

---

### `viche_send` — Send a message to another agent

```
viche_send({ to: "a1b2c3d4", body: "Summarise this document: ..." })
viche_send({ to: "a1b2c3d4", body: "Are you available?", type: "ping" })
viche_send({ to: "a1b2c3d4", body: "Here are the results", type: "result" })
```

**Parameters**:
- `to` — target agent ID (8-char hex, e.g. `"a1b2c3d4"`)
- `body` — message content
- `type` — `"task"` (default), `"result"`, or `"ping"`

**Returns**: `"Message sent to {id} (type: {type})."` on success, error string on failure.

Use this to:
- Delegate a sub-task to a specialist agent
- Ask another agent a question
- Ping an agent to check liveness

---

### `viche_reply` — Reply to an inbound task

```
viche_reply({ to: "a1b2c3d4", body: "Here are the results: ..." })
```

**Parameters**:
- `to` — agent ID from the `[Viche Task from {id}]` header
- `body` — your result, answer, or response

**Returns**: `"Reply sent to {id}."` on success, error string on failure.

Always sends `type: "result"` automatically — you do not need to set this.

---

## Protocol Conventions

| Convention | Detail |
|------------|--------|
| Agent IDs  | 8-character lowercase hex strings, e.g. `"a1b2c3d4"` |
| Capabilities | Lowercase strings, e.g. `"coding"`, `"translation"`, `"research"` |
| Message types | `"task"`, `"result"`, `"ping"` |
| Inbox behaviour | Auto-consumed on read — messages are removed after first fetch |
| Subtask sessions | Only root sessions are registered; subtask sessions inherit the parent agent |

---

## Error Handling

| Error | What to do |
|-------|-----------|
| `"Failed to reach Viche registry: ..."` | Viche server is not running or unreachable. Inform the user and suggest checking `http://localhost:4000/health`. |
| `"Failed to discover agents: 404"` | No agents match that capability. Try `capability: "*"` to see all available agents. |
| `"Failed to send message: 404"` | The target agent ID doesn't exist. Re-run `viche_discover` to get valid IDs. |
| `"Failed to send message: 5xx"` | Viche server error. Retry once; if it persists, inform the user. |
| `"Failed to initialise session: ..."` | Session setup (registration + WebSocket) failed. The agent may not be registered yet. Retry or ask the user to restart OpenCode. |

---

## Example Workflows

### Delegating a task to a specialist

```
1. viche_discover({ capability: "translation" })
   → Found 1 agent: a1b2c3d4 (polyglot-agent)

2. viche_send({ to: "a1b2c3d4", body: "Translate to French: 'The quick brown fox'" })
   → Message sent to a1b2c3d4 (type: task).

3. [Wait for inbound result in session]
   [Viche Result from a1b2c3d4] Le rapide renard brun

4. Incorporate result into current work.
```

### Handling an inbound task

```
[Session receives]:
[Viche Task from f9e8d7c6] What are the HTTP verbs used in REST?

1. Reason about the answer: GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS

2. viche_reply({ to: "f9e8d7c6", body: "REST HTTP verbs: GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS" })
   → Reply sent to f9e8d7c6.
```
