# Spec 12: OpenClaw Plugin Backward Compatibility (v2026.2.1+)

> Lower OpenClaw plugin version requirement from `>=2026.3.22` to `>=2026.2.1` by eliminating all runtime imports from the OpenClaw SDK. Depends on: [11-openclaw-plugin](./11-openclaw-plugin.md)

## Overview

The `openclaw-plugin-viche` currently requires OpenClaw `>=2026.3.22` because it imports `definePluginEntry()` from `openclaw/plugin-sdk/plugin-entry` — a helper introduced in the March 23, 2026 SDK restructure. This spec documents the plan to lower the version requirement to `>=2026.2.1` (published Feb 2, 2026) by:

1. **Removing the single runtime import** (`definePluginEntry`) and exporting a plain object literal instead
2. **Defining all OpenClaw types locally** to eliminate type-only imports from the SDK
3. **Updating `peerDependencies`** to reflect the new minimum version

This change provides **~2 months of backward compatibility** without sacrificing functionality, since the underlying runtime API contract (tool registration, service lifecycle, config schema) has been stable since v2026.2.1.

## Motivation

### Problem

Users running OpenClaw versions between `2026.2.1` and `2026.3.21` cannot install the Viche plugin because of the hard `>=2026.3.22` peer dependency. This excludes a significant portion of the OpenClaw user base from using Viche agent networking.

### Why This Works

The March 23, 2026 SDK restructure (`v2026.3.22`) was **purely cosmetic** — it reorganized import paths and introduced helper functions, but the **runtime API contract remained identical**:

| API Surface | v2026.3.13 (old) | v2026.3.22 (new) | Notes |
|-------------|:----------------:|:----------------:|-------|
| `api.registerTool((ctx) => tool)` | ✅ | ✅ | Factory pattern unchanged |
| `ctx.sessionKey` in tool context | ✅ | ✅ | Same type, same behavior |
| `api.registerService({ id, start, stop })` | ✅ | ✅ | Service interface identical |
| `api.pluginConfig` | ✅ | ✅ | `Record<string, unknown> \| undefined` |
| `api.runtime.subagent.run(...)` | ✅ | ✅ | `SubagentRunParams` unchanged |
| `configSchema.safeParse` + `jsonSchema` | ✅ | ✅ | Schema contract identical |
| `api.config` (OpenClawConfig) | ✅ | ✅ | Present on `OpenClawPluginApi` |
| `api.runtime` (PluginRuntime) | ✅ | ✅ | Present on `OpenClawPluginApi` |

**Key insight:** The plugin currently has exactly **one runtime import** from OpenClaw:

```typescript
import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";  // RUNTIME
```

Everything else is `import type` (erased at compile time). Since OpenClaw loads the plugin and passes the API object at runtime, we can eliminate this import by exporting a plain object literal — the format used by all plugins before v2026.3.22.

### What Changed in v2026.3.22

| Concern | v2026.3.13 (old) | v2026.3.22 (new) |
|---------|------------------|------------------|
| Plugin entry | `export default { id, name, ... }` — plain object | `export default definePluginEntry({ ... })` — wrapper function |
| Type import path | `openclaw/plugin-sdk/compat` or `openclaw/plugin-sdk/<channel>` | `openclaw/plugin-sdk/plugin-entry` |
| `openclaw/extension-api` | Existed (bridge shim) | Removed (no compat layer) |
| Runtime APIs | Identical | Identical |

The `definePluginEntry()` wrapper is just a thin normalizer — it validates the plugin object shape and returns it unchanged. OpenClaw's plugin loader accepts both formats (plain object and wrapped object) for backward compatibility.

## Current State

### Import Analysis

**`index.ts`:**
```typescript
import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";  // RUNTIME ❌
import type { VicheConfig, VicheState, PluginRuntime } from "./types.js";  // Local types ✅
```

**`service.ts`:**
```typescript
import type {
  OpenClawPluginService,
  OpenClawPluginServiceContext,
  PluginLogger,
} from "openclaw/plugin-sdk/plugin-entry";  // Type-only (erased) ⚠️
```

**`tools.ts`:**
```typescript
import type { AnyAgentTool, OpenClawPluginApi } from "openclaw/plugin-sdk/plugin-entry";  // Type-only (erased) ⚠️
```

**`types.ts`:**
```typescript
// No OpenClaw imports — all types defined locally ✅
```

### Dependency on OpenClaw SDK

- **Runtime dependency:** `definePluginEntry()` only
- **Type-only dependencies:** `OpenClawPluginService`, `OpenClawPluginServiceContext`, `PluginLogger`, `AnyAgentTool`, `OpenClawPluginApi`
- **Current peer dependency:** `openclaw >= 2026.3.22`

## Changes Required

### Strategy: Zero Runtime Imports

Since OpenClaw loads the plugin and passes the API object at runtime, the plugin only needs to export the correct **shape** — pure duck typing. We eliminate all imports from OpenClaw by:

1. **Exporting a plain object literal** instead of calling `definePluginEntry()`
2. **Defining all needed types locally** in `types.ts`
3. **Lowering the peer dependency** to `>=2026.2.1`

### 1. Remove `definePluginEntry()` Import

**Before (`index.ts`):**
```typescript
import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";

export default definePluginEntry({
  id: "viche",
  name: "Viche Agent Network",
  description: "...",
  configSchema: VicheConfigSchema,
  register(api) { ... },
});
```

**After (`index.ts`):**
```typescript
// No imports from openclaw — export plain object literal
export default {
  id: "viche",
  name: "Viche Agent Network",
  description: "...",
  configSchema: VicheConfigSchema,
  register(api) { ... },
};
```

This format was used by all plugins before v2026.3.22, and the new OpenClaw still accepts it (since `definePluginEntry` is just a thin wrapper).

### 2. Define OpenClaw Types Locally

Add minimal type interfaces to `types.ts` for the OpenClaw APIs the plugin uses. These are **duck-typed contracts** — as long as the shape matches, the plugin works.

**Add to `types.ts`:**

```typescript
// ---------------------------------------------------------------------------
// OpenClaw Plugin SDK types (local declarations for backward compatibility)
// ---------------------------------------------------------------------------

/**
 * Minimal subset of OpenClawPluginApi used by the Viche plugin.
 * Declared locally to avoid importing from openclaw/plugin-sdk.
 */
export interface OpenClawPluginApi {
  /** Raw plugin config from openclaw.json (before schema validation). */
  pluginConfig?: Record<string, unknown>;
  /** Register a background service (lifecycle: start/stop). */
  registerService(service: OpenClawPluginService): void;
  /** Register an agent tool (factory pattern: (ctx) => tool). */
  registerTool(factory: (ctx: OpenClawPluginToolContext) => AnyAgentTool): void;
  /** OpenClaw runtime APIs (subagent spawning, etc). */
  runtime: PluginRuntime;
  /** Full OpenClaw config object. */
  config: unknown;
}

/**
 * Background service interface for OpenClaw plugins.
 * Services run for the lifetime of the Gateway and manage long-lived resources.
 */
export interface OpenClawPluginService {
  /** Unique service ID (used in logs). */
  id: string;
  /** Called when the Gateway starts. Throw to prevent startup. */
  start(ctx: OpenClawPluginServiceContext): Promise<void>;
  /** Called when the Gateway stops. Clean up resources here. */
  stop(ctx: OpenClawPluginServiceContext): Promise<void>;
}

/**
 * Context passed to service start/stop methods.
 */
export interface OpenClawPluginServiceContext {
  /** Logger instance for this service. */
  logger: PluginLogger;
}

/**
 * Logger interface provided to plugin services.
 */
export interface PluginLogger {
  info(message: string): void;
  warn(message: string): void;
  error(message: string): void;
}

/**
 * Context passed to tool factory functions.
 * Contains the session key of the agent invoking the tool.
 */
export interface OpenClawPluginToolContext {
  /** Session key (e.g. "agent:main:main") of the invoking agent. */
  sessionKey?: string;
}

/**
 * Agent tool type (opaque — cast through `unknown` to avoid deep type dependencies).
 * The actual shape is defined by @mariozechner/pi-agent-core's AgentTool<T, R>.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type AnyAgentTool = any;

/**
 * Config schema interface required by OpenClaw plugins.
 * Must provide `safeParse` for validation and `jsonSchema` for UI generation.
 */
export interface OpenClawPluginConfigSchema<T = unknown> {
  safeParse(value: unknown): { success: true; data: T } | { success: false; error: { issues: Array<{ path: Array<string | number>; message: string }> } };
  jsonSchema: Record<string, unknown>;
}
```

**Update existing `PluginRuntime` type:**

```typescript
/**
 * OpenClaw PluginRuntime object passed to services.
 * Provides access to subagent spawning and other runtime APIs.
 */
export interface PluginRuntime {
  subagent: {
    run(params: {
      sessionKey: string;
      message: string;
      deliver: boolean;
      idempotencyKey: string;
    }): Promise<{ runId: string }>;
  };
}
```

### 3. Update Imports in Plugin Files

**`service.ts` — remove OpenClaw imports:**

```typescript
// Before:
import type {
  OpenClawPluginService,
  OpenClawPluginServiceContext,
  PluginLogger,
} from "openclaw/plugin-sdk/plugin-entry";

// After:
import type {
  OpenClawPluginService,
  OpenClawPluginServiceContext,
  PluginLogger,
} from "./types.js";
```

**`tools.ts` — remove OpenClaw imports:**

```typescript
// Before:
import type { AnyAgentTool, OpenClawPluginApi } from "openclaw/plugin-sdk/plugin-entry";

// After:
import type { AnyAgentTool, OpenClawPluginApi, OpenClawPluginToolContext } from "./types.js";
```

**Update `ToolContext` type alias:**

```typescript
// Before:
type ToolContext = {
  sessionKey?: string;
};

// After (use the imported type):
// Remove the local alias — use OpenClawPluginToolContext from types.ts
```

### 4. Update `package.json`

**Before:**
```json
{
  "peerDependencies": {
    "openclaw": ">=2026.3.22"
  }
}
```

**After:**
```json
{
  "peerDependencies": {
    "openclaw": ">=2026.2.1"
  }
}
```

### 5. Update `VicheConfigSchema` Type Signature

The `VicheConfigSchema` object already implements the required shape (`safeParse` + `jsonSchema`), but we should add an explicit type annotation for clarity:

**Update in `types.ts`:**

```typescript
// Before:
export const VicheConfigSchema = {
  safeParse(value: unknown): SafeParseResult { ... },
  jsonSchema: { ... },
} as const;

// After:
export const VicheConfigSchema: OpenClawPluginConfigSchema<VicheConfig> = {
  safeParse(value: unknown): SafeParseResult { ... },
  jsonSchema: { ... },
};
```

## File Changes Summary

| File | Changes |
|------|---------|
| `index.ts` | Remove `definePluginEntry` import; export plain object literal |
| `service.ts` | Change type imports from `openclaw/plugin-sdk/plugin-entry` to `./types.js` |
| `tools.ts` | Change type imports from `openclaw/plugin-sdk/plugin-entry` to `./types.js`; remove local `ToolContext` alias |
| `types.ts` | Add local OpenClaw type declarations (`OpenClawPluginApi`, `OpenClawPluginService`, etc.); update `PluginRuntime` from `any` to proper interface; add type annotation to `VicheConfigSchema` |
| `package.json` | Change `peerDependencies.openclaw` from `>=2026.3.22` to `>=2026.2.1` |

## Risks & Considerations

### 1. No Compile-Time Type Checking Against OpenClaw

**Risk:** The local type declarations are our contract. If OpenClaw changes the API in a future version, we won't get type errors at compile time.

**Mitigation:**
- The API has been stable for months (since v2026.2.1)
- We can add integration tests that verify the plugin works against multiple OpenClaw versions
- The plugin already uses duck typing for `PluginRuntime` (typed as `any` in current code)

### 2. `configSchema` Contract Changes

**Risk:** If a future OpenClaw version adds required fields to the `OpenClawPluginConfigSchema` interface, our local declaration won't reflect them.

**Mitigation:**
- Low risk — the `safeParse`/`jsonSchema` shape is a well-established pattern (used by Zod, TypeBox, etc.)
- The Viche plugin implements its own `safeParse` logic, so it's not dependent on OpenClaw's validation

### 3. Plugin Discovery on Older Versions

**Risk:** Older OpenClaw versions may have different plugin loading behavior.

**Mitigation:**
- The plain object export format is the **original format** used before v2026.3.22, so this is actually safer
- OpenClaw's plugin loader is designed to accept both formats for backward compatibility

### 4. `openclaw/plugin-sdk/compat` Deprecation Warnings

**Risk:** Older OpenClaw versions may log deprecation warnings if they detect the old import paths.

**Mitigation:**
- Not our concern — we're not importing from OpenClaw at all
- The plugin uses a plain object export, which is the canonical format

## Test Plan

### 1. Verify Plugin Loads on v2026.2.1

- Install OpenClaw v2026.2.1 (or the earliest available version >= 2026.2.1)
- Install the updated Viche plugin
- Start the Gateway
- **Pass criteria:** Plugin registers successfully, no errors in logs

### 2. Verify Plugin Loads on v2026.3.22+

- Install OpenClaw v2026.3.22 (current latest)
- Install the updated Viche plugin
- Start the Gateway
- **Pass criteria:** Plugin registers successfully, no errors in logs

### 3. Verify Service Lifecycle

- Start Gateway with Viche plugin enabled
- Check logs for: `"Viche: registered as {agentId}, connected via WebSocket"`
- Stop Gateway
- Check logs for: `"Viche: disconnected and cleaned up"`
- **Pass criteria:** Service starts and stops cleanly on both v2026.2.1 and v2026.3.22

### 4. Verify Tool Registration

- Start Gateway with Viche plugin enabled
- Query available tools via OpenClaw API
- **Pass criteria:** `viche_discover`, `viche_send`, `viche_reply` are listed

### 5. Verify Tool Execution

- Call `viche_discover("*")` from an agent session
- **Pass criteria:** Returns agent list (or "No agents found")
- Call `viche_send(to: "test-id", body: "hello", type: "task")`
- **Pass criteria:** Returns error (agent not found) or success message

### 6. Verify Config Schema Validation

- Configure plugin with invalid config (e.g. `capabilities: "not-an-array"`)
- Start Gateway
- **Pass criteria:** Plugin fails to load with clear error message listing validation issues

### 7. Verify Type Safety (Compile-Time)

- Run `npm run build` (TypeScript compilation)
- **Pass criteria:** No type errors, clean build

### 8. Integration Test (Full Round-Trip)

- Start Viche registry (`mix phx.server`)
- Start OpenClaw v2026.2.1 with Viche plugin
- Start OpenClaw v2026.3.22 with Viche plugin
- From v2026.3.22 instance, call `viche_discover("coding")`
- **Pass criteria:** Finds the v2026.2.1 instance
- From v2026.3.22 instance, call `viche_send` to v2026.2.1 instance
- **Pass criteria:** Message delivered, v2026.2.1 instance receives it via WebSocket

## Version Target Rationale

### Why v2026.2.1?

- **Published:** Feb 2, 2026 — nearly 2 months before the breaking SDK restructure (March 23, 2026)
- **API stability:** The plugin SDK with `registerTool` factory, `registerService`, `runtime.subagent.run`, `pluginConfig`, and `configSchema` all existed at this version
- **User coverage:** Provides ~2 months of backward compatibility, covering users who haven't upgraded to the latest OpenClaw

### Why Not Earlier?

- **v2026.1.x:** The tool factory pattern `(ctx) => tool` was introduced in v2026.2.1. Earlier versions used a different registration API.
- **v2025.x:** Significant API differences in service lifecycle and config schema handling.

Going back to v2026.2.1 strikes the right balance between backward compatibility and implementation complexity.

## Comparison: Before vs After

| Aspect | Before (v2026.3.22+) | After (v2026.2.1+) |
|--------|---------------------|-------------------|
| Minimum OpenClaw version | `>=2026.3.22` | `>=2026.2.1` |
| Runtime imports from OpenClaw | 1 (`definePluginEntry`) | 0 |
| Type imports from OpenClaw | 5 (all type-only) | 0 |
| Plugin entry format | `definePluginEntry({ ... })` | `{ ... }` (plain object) |
| Type safety | Full SDK types | Local duck-typed interfaces |
| Backward compatibility | 0 days | ~50 days (Feb 2 → Mar 23) |
| Risk of breakage | Low (SDK types) | Low (stable API contract) |

## Implementation Checklist

- [ ] Add local OpenClaw type declarations to `types.ts`
- [ ] Update `PluginRuntime` from `any` to proper interface in `types.ts`
- [ ] Add type annotation to `VicheConfigSchema` in `types.ts`
- [ ] Remove `definePluginEntry` import from `index.ts`
- [ ] Export plain object literal from `index.ts`
- [ ] Update type imports in `service.ts` to use `./types.js`
- [ ] Update type imports in `tools.ts` to use `./types.js`
- [ ] Remove local `ToolContext` alias from `tools.ts`
- [ ] Update `peerDependencies.openclaw` in `package.json` to `>=2026.2.1`
- [ ] Run `npm run build` — verify clean TypeScript compilation
- [ ] Test plugin on OpenClaw v2026.2.1 (if available)
- [ ] Test plugin on OpenClaw v2026.3.22+
- [ ] Verify service lifecycle (start/stop)
- [ ] Verify tool registration and execution
- [ ] Verify config schema validation
- [ ] Run full integration test (cross-version messaging)
- [ ] Update plugin README with new version requirement
- [ ] Publish updated plugin to npm

## Dependencies

- [11-openclaw-plugin](./11-openclaw-plugin.md) — the plugin being modified
- OpenClaw v2026.2.1+ — target runtime environment
- Viche registry (specs [01](./01-agent-lifecycle.md)-[05](./05-well-known.md)) — unchanged

## Open Questions

1. **Should we test against v2026.2.1 specifically?** — If v2026.2.1 is not easily available, we can test against the earliest available version >= 2026.2.1 and document the actual tested version.

2. **Should we add a CI matrix for multiple OpenClaw versions?** — Ideal for long-term maintenance, but may be overkill for v1. Could be added later if compatibility issues arise.

3. **Should we keep a compatibility table in the README?** — Documenting tested OpenClaw versions would help users understand which versions are known to work.

4. **Should we add runtime version detection?** — The plugin could log a warning if it detects an OpenClaw version < 2026.2.1, but this adds complexity and may not be necessary if the peer dependency is enforced by npm.
