import { describe, it, expect, mock, beforeEach, afterEach } from "bun:test";
import { registerVicheTools } from "./tools.ts";
import { Type } from "@sinclair/typebox";

describe("Argus: SSRF in viche_reply", () => {
  let originalFetch: typeof fetch;

  beforeEach(() => {
    originalFetch = globalThis.fetch;
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  it("should not allow path traversal in the 'to' parameter of viche_reply", async () => {
    let fetchCalledWithUrl = "";

    // Mock global fetch to capture the URL
    globalThis.fetch = mock(async (url: string | URL | Request, options?: RequestInit) => {
      fetchCalledWithUrl = url.toString();
      return new Response(JSON.stringify({}), { status: 200 });
    });

    const mockApi = {
      tools: [] as any[],
      registerTool(factory: any) {
        // Evaluate the factory to get the tool
        const tool = typeof factory === "function" ? factory({ sessionKey: "test-session" }) : factory;
        this.tools.push(tool);
      }
    };

    const config = { registryUrl: "http://internal-registry.local" } as any;
    const state = { agentId: "my-agent", correlations: new Map(), mostRecentSessionKey: null };

    registerVicheTools(mockApi as any, config, state);

    const vicheReplyTool = mockApi.tools.find(t => t.name === "viche_reply");
    expect(vicheReplyTool).toBeDefined();

    // Call viche_reply with a path traversal payload
    const traversalPayload = "../../../admin/delete";
    await vicheReplyTool.execute("call-1", { to: traversalPayload, body: "test" });

    // Ensure fetch was not called with a traversed URL
    // If it was, the test should fail to indicate the vulnerability exists.
    const urlObj = new URL(fetchCalledWithUrl);
    
    // The vulnerability is present if the pathname resolved to /admin/delete instead of /messages/...
    // Note: fetch resolves URLs based on the base URL if it's absolute, but here the URL is constructed via string concatenation:
    // `${config.registryUrl}/messages/${params.to}` -> "http://internal-registry.local/messages/../../../admin/delete"
    // The native URL parsing will resolve this to "http://internal-registry.local/admin/delete"
    
    // Test fails if vulnerability exists (i.e. URL resolves to traversal path)
    expect(urlObj.pathname).not.toBe("/admin/delete");
  });
});