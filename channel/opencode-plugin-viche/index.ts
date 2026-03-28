/**
 * opencode-plugin-viche — Plugin entry point.
 *
 * Wires together config, service, and tools into an OpenCode plugin.
 *
 * Registers:
 *   1. A per-session background service that registers the agent with the
 *      Viche registry and maintains a Phoenix Channel WebSocket for real-time
 *      inbound message delivery.
 *   2. Three agent tools: `viche_discover`, `viche_send`, `viche_reply`.
 *
 * Design notes:
 *   - Config is loaded once at plugin init (not per-session).
 *   - Only ROOT sessions receive a Viche agent registration — subtask sessions
 *     (those with a `parentID`) are intentionally skipped.
 *   - State is shared between the event handler and tools via closure.
 *   - The `@opencode-ai/plugin` package is a peer dep and may not be installed
 *     at runtime, so it is never imported here.
 */

import { loadConfig } from "./config.js";
import { createVicheService } from "./service.js";
import { createVicheTools } from "./tools.js";
import type { VicheState } from "./types.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** Shape of the input provided by the OpenCode plugin loader. */
type PluginInput = {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  client: any;
  directory: string;
};

/** Incoming event from the OpenCode event bus. */
type PluginEvent = {
  type: string;
  properties?: Record<string, unknown>;
};

/** Hooks returned to the OpenCode plugin runtime. */
type PluginHooks = {
  event: (input: { event: PluginEvent }) => Promise<void>;
  tool: Record<string, unknown>;
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Parsed fields from an event's `properties.info` object. */
type SessionEventInfo = {
  id: string | undefined;
  parentID: unknown;
};

/**
 * Safely extract `id` and `parentID` from an event's `properties.info`.
 * Returns `{ id: undefined, parentID: undefined }` for any malformed input.
 */
function getSessionEventInfo(event: PluginEvent): SessionEventInfo {
  const info = event.properties?.["info"];
  if (info == null || typeof info !== "object" || Array.isArray(info)) {
    return { id: undefined, parentID: undefined };
  }
  const record = info as Record<string, unknown>;
  return {
    id: typeof record["id"] === "string" ? record["id"] : undefined,
    parentID: record["parentID"],
  };
}

// ---------------------------------------------------------------------------
// Plugin
// ---------------------------------------------------------------------------

/**
 * OpenCode plugin factory for Viche.
 *
 * @param input.client    - OpenCode SDK client (typed `any` to avoid runtime dep).
 * @param input.directory - Project directory; forwarded to session prompt calls.
 */
const vichePlugin = async ({
  client,
  directory,
}: PluginInput): Promise<PluginHooks> => {
  // Load config once — reads env vars and .opencode/viche.json.
  const config = loadConfig(directory);

  // Shared mutable state: active sessions + in-flight initialisations.
  const state: VicheState = {
    sessions: new Map(),
    initializing: new Map(),
  };

  // Service owns session lifecycle: registration, WebSocket, prompt injection.
  const service = createVicheService(config, state, client, directory);

  // Tools are the three LLM-callable functions exposed to the agent.
  const tools = createVicheTools(config, state, service.ensureSessionReady);

  return {
    /**
     * OpenCode lifecycle event handler.
     *
     * Handles:
     *   - `session.created` — register root sessions only (`parentID == null`)
     *   - `session.deleted` — clean up socket + channel (fire-and-forget)
     */
    async event({ event }: { event: PluginEvent }): Promise<void> {
      const { id, parentID } = getSessionEventInfo(event);

      // No session ID means nothing to act on.
      if (id === undefined) return;

      switch (event.type) {
        case "session.created":
          // Only register root sessions — subtask sessions share the parent's agent.
          if (parentID == null) {
            await service.handleSessionCreated(id);
          }
          return;

        case "session.deleted":
          // Fire-and-forget: cleanup is best-effort and must not block the caller.
          service.handleSessionDeleted(id);
          return;

        default:
          return;
      }
    },

    tool: tools,
  };
};

export default vichePlugin;
