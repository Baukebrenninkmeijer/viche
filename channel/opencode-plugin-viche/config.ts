/**
 * Config loader for opencode-plugin-viche.
 *
 * Precedence (highest → lowest):
 *   1. Environment variables  (VICHE_REGISTRY_URL, VICHE_AGENT_NAME,
 *                               VICHE_CAPABILITIES, VICHE_DESCRIPTION)
 *   2. File: <projectDir>/.opencode/viche.json
 *   3. Built-in defaults
 *
 * The config file is optional — a missing or malformed file is silently
 * ignored and falls back to defaults.
 */

import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { VicheConfig } from "./types.js";

// ---------------------------------------------------------------------------
// Defaults
// ---------------------------------------------------------------------------

const DEFAULT_REGISTRY_URL = "http://localhost:4000";
const DEFAULT_CAPABILITIES = ["coding"] as const;

// ---------------------------------------------------------------------------
// Raw file shape
// ---------------------------------------------------------------------------

/** Shape of the JSON we accept from .opencode/viche.json. */
type RawFileConfig = {
  registryUrl?: unknown;
  capabilities?: unknown;
  agentName?: unknown;
  description?: unknown;
};

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/**
 * Load and parse .opencode/viche.json, returning an empty object on any
 * error (missing file, bad permissions, invalid JSON, non-object root).
 */
function loadFileConfig(projectDir: string): RawFileConfig {
  const configPath = join(projectDir, ".opencode", "viche.json");
  try {
    const raw = readFileSync(configPath, "utf-8");
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
      return {};
    }
    return parsed as RawFileConfig;
  } catch {
    return {};
  }
}

/**
 * Return the first non-blank string among `envVal`, `fileVal`, and
 * `fallback`, trimming each candidate before the emptiness check.
 */
function pickNonBlankString(
  envVal: string | undefined,
  fileVal: unknown,
  fallback: string
): string {
  if (typeof envVal === "string" && envVal.trim().length > 0) {
    return envVal.trim();
  }
  if (typeof fileVal === "string" && fileVal.trim().length > 0) {
    return fileVal.trim();
  }
  return fallback;
}

/**
 * Resolve a capabilities array from env var → file → defaults.
 *
 * `VICHE_CAPABILITIES` is a comma-separated string; each value is trimmed
 * and empty segments are dropped.
 */
function pickCapabilities(
  envVal: string | undefined,
  fileVal: unknown,
  fallback: readonly string[]
): string[] {
  if (typeof envVal === "string" && envVal.trim().length > 0) {
    const parsed = envVal
      .split(",")
      .map((c) => c.trim().toLowerCase())
      .filter(Boolean);
    if (parsed.length > 0) return parsed;
  }
  if (Array.isArray(fileVal)) {
    const filtered = (fileVal as unknown[])
      .map((c) => (typeof c === "string" ? c.trim().toLowerCase() : ""))
      .filter(Boolean);
    if (filtered.length > 0) return filtered;
  }
  return [...fallback];
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Build a `VicheConfig` for the given project directory.
 *
 * @param projectDir  Absolute path to the OpenCode project root.
 */
export function loadConfig(projectDir: string): VicheConfig {
  const fileConfig = loadFileConfig(projectDir);

  const registryUrl = pickNonBlankString(
    process.env.VICHE_REGISTRY_URL,
    fileConfig.registryUrl,
    DEFAULT_REGISTRY_URL
  );

  const capabilities = pickCapabilities(
    process.env.VICHE_CAPABILITIES,
    fileConfig.capabilities,
    DEFAULT_CAPABILITIES
  );

  const agentName =
    pickNonBlankString(
      process.env.VICHE_AGENT_NAME,
      fileConfig.agentName,
      ""
    ) || undefined;

  const description =
    pickNonBlankString(
      process.env.VICHE_DESCRIPTION,
      fileConfig.description,
      ""
    ) || undefined;

  const config: VicheConfig = { registryUrl, capabilities };
  if (agentName !== undefined) config.agentName = agentName;
  if (description !== undefined) config.description = description;

  return config;
}
