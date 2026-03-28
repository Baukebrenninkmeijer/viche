import { describe, it, expect } from "bun:test";
import { registerVicheTools } from "../tools.ts";
import type { VicheConfig, VicheState } from "../types.ts";

describe("Argus: type invariant — DiscoverResponse missing schema validation", () => {
  it("should reject invalid discovery response, but currently crashes", async () => {
    // Arrange
    const state: VicheState = {
      agentId: "a1b2c3d4",
      correlations: new Map(),
      mostRecentSessionKey: null,
    };
    const config: VicheConfig = { registryUrl: "http://localhost", defaultInboundSession: "most-recent" };

    let registeredTool: any = null;
    const apiMock = {
      registerTool: (toolOrFactory: any) => {
        if (typeof toolOrFactory === "function") {
          const tool = toolOrFactory({ sessionKey: "test-session" });
          if (tool.name === "viche_discover") {
            registeredTool = tool;
          }
        }
      },
      addResource: () => {},
      addResourceTemplate: () => {},
    };

    registerVicheTools(apiMock as any, config, state);
    expect(registeredTool).not.toBeNull();

    // Mock fetch to return an invalid DiscoverResponse (agents is an object, not an array)
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async () =>
      new Response(JSON.stringify({ agents: { length: 5, some: "object" } }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });

    let threw = false;
    try {
      // Act
      // The tool execute tries to format the agents. Since it's an object, .map is not a function and it crashes.
      await registeredTool.execute("call-1", { capability: "*" });
    } catch (e) {
      threw = true;
    } finally {
      globalThis.fetch = originalFetch;
    }

    // Assert
    // This test FAILS if the bug exists (the tool crashes instead of returning a clean error result via schema validation).
    // We expect it NOT to throw an unhandled exception but rather return an error result or fail validation.
    // Wait, the test should FAIL if the bug exists, so we expect(threw).toBe(false); 
    // If it threw, that means the bug exists (it crashed).
    expect(threw).toBe(false);
  });
});
