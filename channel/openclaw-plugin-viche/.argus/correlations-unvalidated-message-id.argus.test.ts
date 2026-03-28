import { describe, it, expect, mock, spyOn } from "bun:test";
import { registerVicheTools } from "../tools.ts";
import type { VicheConfig, VicheState } from "../types.ts";

describe("Argus: type invariant — correlations message_id must be a validated string", () => {
  it("should reject invalid message_id from server, but currently accepts it", async () => {
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
          if (tool.name === "viche_send") {
            registeredTool = tool;
          }
        }
      },
      addResource: () => {},
      addResourceTemplate: () => {},
    };

    // Capture the viche_send tool
    registerVicheTools(apiMock as any, config, state);
    expect(registeredTool).not.toBeNull();

    // Mock fetch to return an invalid message_id (e.g. a number or object)
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async () =>
      new Response(JSON.stringify({ message_id: { invalid: "object" } }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });

    try {
      // Act
      await registeredTool.execute("call-1", { to: "a1b2c3d4", body: "hello" });

      // Assert
      // The state map now has a non-string key (an object) because there was no schema validation!
      // This test FAILS if the bug exists (i.e. if it doesn't throw and puts the object in the map).
      // We check if it throws or if the map stays empty. Since it currently doesn't, this expect will fail.
      expect(state.correlations.size).toBe(0);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});
