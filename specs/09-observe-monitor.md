# Spec 09: Observe / Monitor Notifications

> Presence awareness for the agent network. Depends on: [01-agent-lifecycle](./01-agent-lifecycle.md), [07-websockets](./07-websockets.md), [08-auto-deregister](./08-auto-deregister.md)

**Status: Future — not yet implemented**

## Overview

Agents can subscribe to registry-level events (agent registered, agent deregistered) to build presence awareness. When an agent joins or leaves the network, subscribed agents receive a notification via their Phoenix Channel. This enables coordination patterns like "wait for a coding agent to come online" or "reassign work when an agent disappears."

## Motivation

Today, agents can only discover each other via explicit `discover` queries — there's no way to know when the network topology changes. With auto-deregistration (Spec 08) removing stale agents, the network becomes dynamic. Observe/monitor notifications close the loop: agents can react to changes instead of polling for them.

This mirrors Erlang/OTP's `Process.monitor/1` semantics, lifted to the agent registry level.

## Rough Idea

- New Channel event: `"subscribe_registry"` — agent opts in to registry notifications
- Server → client events: `"agent_registered"` and `"agent_deregistered"` pushed to subscribers
- Payload includes agent ID, name, and capabilities (so subscribers can filter client-side)
- Subscription is per-connection — if the WebSocket disconnects, the subscription is lost
- Consider using Phoenix PubSub with a dedicated `"registry_events"` topic internally
- Long-polling agents could have a `GET /registry/events` endpoint (or skip — WebSocket-only feature)

## Dependencies

- [01-agent-lifecycle](./01-agent-lifecycle.md) — registration events
- [07-websockets](./07-websockets.md) — Channel infrastructure for pushing events
- [08-auto-deregister](./08-auto-deregister.md) — deregistration events to broadcast
