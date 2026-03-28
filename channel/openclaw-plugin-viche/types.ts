/**
 * Shared types and config schema for openclaw-plugin-viche.
 *
 * VicheConfigSchema implements OpenClawPluginConfigSchema (safeParse + jsonSchema).
 * TypeBox TObject is a plain JSON Schema object and does NOT implement
 * OpenClawPluginConfigSchema, so we build the schema manually.
 */

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

/** Plugin configuration provided via openclaw.json `plugins.viche.config`. */
export interface VicheConfig {
  /** Viche registry base URL. Default: "http://localhost:4000" */
  registryUrl: string;
  /** Agent capabilities to register. Default: ["coding"] */
  capabilities: string[];
  /** Optional human-readable agent name. */
  agentName?: string;
  /** Optional agent description. */
  description?: string;
  /**
   * OpenClaw hooks token used for webhook injection (`POST /hooks/agent`).
   * Falls back to `config.hooks.token` from the main OpenClaw config when omitted.
   */
  hooksToken?: string;
  /**
   * OpenClaw gateway URL used for webhook injection.
   * Default: "http://127.0.0.1:18789"
   */
  gatewayUrl?: string;
}

/** Defaults applied when config fields are omitted. */
const CONFIG_DEFAULTS: { registryUrl: string; capabilities: string[]; gatewayUrl: string } = {
  registryUrl: "http://localhost:4000",
  capabilities: ["coding"],
  gatewayUrl: "http://127.0.0.1:18789",
};

type Issue = { path: Array<string | number>; message: string };
type SafeParseResult =
  | { success: true; data: VicheConfig }
  | { success: false; error: { issues: Issue[] } };

function issue(path: Array<string | number>, message: string): SafeParseResult {
  return { success: false, error: { issues: [{ path, message }] } };
}

/**
 * OpenClawPluginConfigSchema implementation for VicheConfig.
 * Validates, normalises, and applies defaults to raw plugin config values.
 */
export const VicheConfigSchema = {
  safeParse(value: unknown): SafeParseResult {
    // Allow undefined / null → full defaults
    if (value === undefined || value === null) {
      return { success: true, data: { ...CONFIG_DEFAULTS } };
    }

    if (typeof value !== "object" || Array.isArray(value)) {
      return issue([], "plugin config must be an object");
    }

    const raw = value as Record<string, unknown>;

    // registryUrl
    if (raw.registryUrl !== undefined && typeof raw.registryUrl !== "string") {
      return issue(["registryUrl"], "must be a string");
    }

    // capabilities
    if (raw.capabilities !== undefined) {
      if (
        !Array.isArray(raw.capabilities) ||
        !raw.capabilities.every((c) => typeof c === "string")
      ) {
        return issue(["capabilities"], "must be an array of strings");
      }
    }

    // agentName
    if (raw.agentName !== undefined && typeof raw.agentName !== "string") {
      return issue(["agentName"], "must be a string");
    }

    // description
    if (raw.description !== undefined && typeof raw.description !== "string") {
      return issue(["description"], "must be a string");
    }

    // hooksToken
    if (raw.hooksToken !== undefined && typeof raw.hooksToken !== "string") {
      return issue(["hooksToken"], "must be a string");
    }

    // gatewayUrl
    if (raw.gatewayUrl !== undefined && typeof raw.gatewayUrl !== "string") {
      return issue(["gatewayUrl"], "must be a string");
    }

    const normalized: VicheConfig = {
      registryUrl:
        typeof raw.registryUrl === "string"
          ? raw.registryUrl
          : CONFIG_DEFAULTS.registryUrl,
      capabilities: Array.isArray(raw.capabilities)
        ? (raw.capabilities as string[])
        : CONFIG_DEFAULTS.capabilities,
    };

    // Only assign optional string properties when present to satisfy exactOptionalPropertyTypes.
    const gatewayUrl = typeof raw.gatewayUrl === "string" ? raw.gatewayUrl : CONFIG_DEFAULTS.gatewayUrl;
    if (gatewayUrl !== undefined) normalized.gatewayUrl = gatewayUrl;
    if (typeof raw.agentName === "string") normalized.agentName = raw.agentName;
    if (typeof raw.description === "string") normalized.description = raw.description;
    if (typeof raw.hooksToken === "string") normalized.hooksToken = raw.hooksToken;

    return { success: true, data: normalized };
  },

  jsonSchema: {
    type: "object",
    additionalProperties: false,
    properties: {
      registryUrl: {
        type: "string",
        default: "http://localhost:4000",
        description: "Viche registry base URL",
      },
      capabilities: {
        type: "array",
        items: { type: "string" },
        default: ["coding"],
        description: "Capability strings this agent publishes to the Viche registry",
      },
      agentName: {
        type: "string",
        description: "Human-readable agent name shown in discovery results",
      },
      description: {
        type: "string",
        description: "Short description of this agent",
      },
      hooksToken: {
        type: "string",
        description:
          "OpenClaw hooks token for webhook injection. Defaults to config.hooks.token.",
      },
      gatewayUrl: {
        type: "string",
        default: "http://127.0.0.1:18789",
        description: "OpenClaw gateway URL for inbound message injection",
      },
    },
  },
} as const;

// ---------------------------------------------------------------------------
// Shared runtime state
// ---------------------------------------------------------------------------

/**
 * Mutable state shared between the background service and the tool handlers.
 * The service sets `agentId` on successful registration and clears it on stop.
 */
export interface VicheState {
  agentId: string | null;
}

// ---------------------------------------------------------------------------
// Agent tool result shape (matches @mariozechner/pi-agent-core AgentToolResult)
// ---------------------------------------------------------------------------

export type AgentToolResult = {
  content: Array<{ type: string; text: string }>;
  details?: unknown;
};

// ---------------------------------------------------------------------------
// Viche API response shapes
// ---------------------------------------------------------------------------

export interface AgentInfo {
  id: string;
  name?: string;
  capabilities?: string[];
  description?: string;
}

export interface DiscoverResponse {
  agents: AgentInfo[];
}

export interface RegisterResponse {
  id: string;
}

export interface InboundMessagePayload {
  id: string;
  from: string;
  body: string;
  type: string;
}
