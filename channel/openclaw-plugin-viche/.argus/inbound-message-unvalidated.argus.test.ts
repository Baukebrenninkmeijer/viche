import { describe, it, expect, mock } from "bun:test";

let messageHandler: ((payload: any) => void) | null = null;

// Mock the phoenix Socket before importing the service
mock.module("phoenix", () => {
  return {
    Socket: class {
      connect() {}
      onOpen(cb: any) { setTimeout(cb, 10); } // trigger open
      onError() {}
      onClose() {}
      channel() {
        return {
          on: (event: string, cb: any) => {
            if (event === "new_message") {
              messageHandler = cb;
            }
          },
          join: () => {
            const receiveChain = {
              receive: (status: string, cb: any) => {
                if (status === "ok") setTimeout(cb, 0);
                return receiveChain;
              }
            };
            return receiveChain;
          }
        };
      }
    }
  };
});

import { createVicheService } from "../service.ts";
import type { VicheConfig, VicheState } from "../types.ts";

describe("Argus: type invariant — InboundMessagePayload missing schema validation", () => {
  it("should reject an invalid payload, but currently accepts it", async () => {
    const state: VicheState = {
      agentId: null,
      correlations: new Map(),
      mostRecentSessionKey: null,
    };
    const config: VicheConfig = { registryUrl: "http://localhost", defaultInboundSession: "most-recent" };

    const runtimeMock = {
      subagent: {
        run: async () => ({ runId: "test-run" })
      }
    };
    const loggerMock = { info: () => {}, error: () => {}, warn: () => {} };
    const apiMock: any = { runtime: runtimeMock };

    // Mock fetch for registration
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async () =>
      new Response(JSON.stringify({ id: "a1b2c3d4" }), { status: 200 });

    try {
      const service = createVicheService(config, state, runtimeMock as any, {});
      await service.start({ logger: loggerMock } as any);
      
      // Wait for socket to trigger and save handler
      await new Promise(r => setTimeout(r, 20));

      expect(messageHandler).not.toBeNull();

      // Arrange an invalid payload object (e.g., missing required fields like `body`, `from`, `id`)
      const invalidPayload = { type: "task" }; // Missing required fields

      // Act: Inject the invalid payload via the message handler.
      // If there was boundary validation, it would throw or reject.
      // Since there's none, it processes it and likely passes `undefined` string values forward.
      let didThrow = false;
      try {
        await messageHandler!(invalidPayload);
      } catch (e) {
        didThrow = true;
      }

      // Assert: This expect FAILS if it accepted the invalid payload without throwing.
      expect(didThrow).toBe(true);

    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});
