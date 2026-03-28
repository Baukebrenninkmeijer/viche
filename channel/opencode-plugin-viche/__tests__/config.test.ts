/**
 * Tests for loadConfig — covers file loading, env var overrides, defaults,
 * validation, and precedence rules.
 *
 * Uses real temp directories for file-based cases so we exercise actual fs
 * reads. Env vars are saved/restored around every test.
 */

import { describe, it, expect, beforeEach, afterEach } from "bun:test";
import { mkdirSync, writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { loadConfig } from "../config.js";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const ENV_KEYS = [
  "VICHE_REGISTRY_URL",
  "VICHE_AGENT_NAME",
  "VICHE_CAPABILITIES",
  "VICHE_DESCRIPTION",
] as const;

type SavedEnv = Record<(typeof ENV_KEYS)[number], string | undefined>;

/** Create a temp projectDir, optionally writing .opencode/viche.json. */
function makeTempDir(config?: unknown): string {
  const dir = join(
    tmpdir(),
    `opencode-plugin-viche-${Date.now()}-${Math.random().toString(36).slice(2)}`
  );
  mkdirSync(dir, { recursive: true });
  if (config !== undefined) {
    mkdirSync(join(dir, ".opencode"), { recursive: true });
    writeFileSync(join(dir, ".opencode", "viche.json"), JSON.stringify(config));
  }
  return dir;
}

// ---------------------------------------------------------------------------
// Suite
// ---------------------------------------------------------------------------

describe("loadConfig", () => {
  let savedEnv: SavedEnv;
  let tempDir: string | undefined;

  beforeEach(() => {
    savedEnv = {} as SavedEnv;
    for (const key of ENV_KEYS) {
      savedEnv[key] = process.env[key];
      delete process.env[key];
    }
    tempDir = undefined;
  });

  afterEach(() => {
    for (const key of ENV_KEYS) {
      if (savedEnv[key] === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = savedEnv[key];
      }
    }
    if (tempDir) {
      rmSync(tempDir, { recursive: true, force: true });
      tempDir = undefined;
    }
  });

  // ── 1. Pure defaults ───────────────────────────────────────────────────────

  it("returns defaults when there is no config file and no env vars", () => {
    tempDir = makeTempDir(); // no viche.json
    const cfg = loadConfig(tempDir);

    expect(cfg.registryUrl).toBe("http://localhost:4000");
    expect(cfg.capabilities).toEqual(["coding"]);
    expect(cfg.agentName).toBeUndefined();
    expect(cfg.description).toBeUndefined();
  });

  // ── 2. File loading ────────────────────────────────────────────────────────

  it("reads all values from .opencode/viche.json", () => {
    tempDir = makeTempDir({
      registryUrl: "http://viche.example.com",
      capabilities: ["code-review", "translation"],
      agentName: "my-agent",
      description: "A test agent",
    });

    const cfg = loadConfig(tempDir);

    expect(cfg.registryUrl).toBe("http://viche.example.com");
    expect(cfg.capabilities).toEqual(["code-review", "translation"]);
    expect(cfg.agentName).toBe("my-agent");
    expect(cfg.description).toBe("A test agent");
  });

  // ── 3. Env var override ────────────────────────────────────────────────────

  it("env vars override file values when both are set", () => {
    tempDir = makeTempDir({
      registryUrl: "http://from-file.example.com",
      capabilities: ["from-file"],
      agentName: "file-agent",
      description: "from file",
    });
    process.env.VICHE_REGISTRY_URL = "http://from-env.example.com";
    process.env.VICHE_CAPABILITIES = "from-env,another";
    process.env.VICHE_AGENT_NAME = "env-agent";
    process.env.VICHE_DESCRIPTION = "from env";

    const cfg = loadConfig(tempDir);

    expect(cfg.registryUrl).toBe("http://from-env.example.com");
    expect(cfg.capabilities).toEqual(["from-env", "another"]);
    expect(cfg.agentName).toBe("env-agent");
    expect(cfg.description).toBe("from env");
  });

  // ── 4. VICHE_CAPABILITIES comma-splitting ──────────────────────────────────

  it("splits VICHE_CAPABILITIES on commas and trims whitespace", () => {
    tempDir = makeTempDir();
    process.env.VICHE_CAPABILITIES = "coding,research,testing";

    const cfg = loadConfig(tempDir);

    expect(cfg.capabilities).toEqual(["coding", "research", "testing"]);
  });

  // ── 5. Empty capabilities fall back to default ─────────────────────────────

  it("falls back to default capabilities when file has an empty array", () => {
    tempDir = makeTempDir({ capabilities: [] });

    const cfg = loadConfig(tempDir);

    expect(cfg.capabilities).toEqual(["coding"]);
  });

  // ── 6. Invalid registryUrl type falls back to default ─────────────────────

  it("falls back to default registryUrl when file value is not a string", () => {
    tempDir = makeTempDir({ registryUrl: 42 });

    const cfg = loadConfig(tempDir);

    expect(cfg.registryUrl).toBe("http://localhost:4000");
  });

  // ── 7. Full precedence: env > file > defaults ──────────────────────────────

  it("env vars take full precedence: env > file > defaults", () => {
    tempDir = makeTempDir({
      registryUrl: "http://file.example.com",
      capabilities: ["file-cap"],
      agentName: "file-agent",
      description: "from file",
    });
    process.env.VICHE_REGISTRY_URL = "http://env.example.com";
    process.env.VICHE_AGENT_NAME = "env-agent";
    process.env.VICHE_CAPABILITIES = "env-cap";
    process.env.VICHE_DESCRIPTION = "from env";

    const cfg = loadConfig(tempDir);

    expect(cfg.registryUrl).toBe("http://env.example.com");
    expect(cfg.capabilities).toEqual(["env-cap"]);
    expect(cfg.agentName).toBe("env-agent");
    expect(cfg.description).toBe("from env");
  });

  // ── 8. Graceful on missing file ────────────────────────────────────────────

  it("does not throw when .opencode/viche.json is missing", () => {
    tempDir = makeTempDir(); // directory exists, no viche.json inside

    expect(() => loadConfig(tempDir!)).not.toThrow();
    expect(loadConfig(tempDir!).registryUrl).toBe("http://localhost:4000");
  });

  // ── 9. Graceful on invalid JSON ────────────────────────────────────────────

  it("falls back to defaults when .opencode/viche.json contains invalid JSON", () => {
    const dir = join(
      tmpdir(),
      `opencode-plugin-viche-invalid-${Date.now()}`
    );
    mkdirSync(join(dir, ".opencode"), { recursive: true });
    writeFileSync(join(dir, ".opencode", "viche.json"), "{ not valid json }}}");
    tempDir = dir;

    const cfg = loadConfig(tempDir);

    expect(cfg.registryUrl).toBe("http://localhost:4000");
    expect(cfg.capabilities).toEqual(["coding"]);
  });
});
