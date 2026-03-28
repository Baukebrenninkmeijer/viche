import { describe, it, expect, mock, beforeEach, afterEach } from "bun:test";

const mockChannel = {
  on: mock((event, callback) => {}),
  join: () => ({ receive: (status: string, cb: any) => { if (status === "ok") cb(); return mockChannel.join(); } })
};

const mockSocket = {
  connect: mock(() => {}),
  channel: mock(() => mockChannel),
  onOpen: mock((cb) => cb()),
  onError: mock((cb) => {}),
  onClose: mock((cb) => {})
};

mock.module("phoenix", () => {
  return {
    Socket: class {
      constructor() { return mockSocket; }
    }
  };
});

import { createVicheService } from "./service.ts";
import { registerVicheTools } from "./tools.ts";

describe("Argus: Cross-Session Message Injection (most-recent policy leak)", () => {
  let originalFetch: typeof fetch;

  beforeEach(() => {
    originalFetch = globalThis.fetch;
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  it("should inject an unsolicited message into a different user's session if they recently used viche", async () => {
    const state = {
      agentId: "my-agent",
      correlations: new Map(),
      mostRecentSessionKey: null,
    };
    const config = { registryUrl: "http://local", defaultInboundSession: "most-recent" } as any;

    const mockApi = {
      tools: [] as any[],
      registerTool(factory: any) {
        this.tools.push(factory);
      }
    };

    registerVicheTools(mockApi as any, config, state);

    // User A uses viche_send, which updates the shared global state
    const userASessionKey = "agent:tenant-a:session-1";
    const vicheSendFactory = mockApi.tools.find(t => {
      const tool = t({ sessionKey: "dummy" });
      return tool.name === "viche_send";
    });
    
    expect(vicheSendFactory).toBeDefined();
    const userATool = vicheSendFactory({ sessionKey: userASessionKey });

    globalThis.fetch = mock(async () => new Response(JSON.stringify({ message_id: "msg-1" }), { status: 200 }));
    
    await userATool.execute("call-1", { to: "some-agent", body: "hello" });
    
    // Validate that User A's session is now globally remembered
    expect(state.mostRecentSessionKey).toBe(userASessionKey);

    // Mock runtime for service
    let injectedSessionKey: string | undefined;
    const runtimeMock = {
      subagent: {
        run: mock(async (opts: any) => {
          injectedSessionKey = opts.sessionKey;
          return { runId: "run-123" };
        })
      }
    };

    const loggerMock = { info: () => {}, error: () => {}, warn: () => {} };

    // Fix signature: config, state, runtime, _openclawConfig
    const service = createVicheService(config, state, runtimeMock as any, {});
    globalThis.fetch = mock(async () => new Response(JSON.stringify({ id: "my-agent", capabilities: [] }), { status: 200 }));
    
    // Start service
    const startPromise = service.start({ logger: loggerMock } as any);
    
    // Wait for event handler registration
    await new Promise(r => setTimeout(r, 10));

    // Find the new_message callback
    const onCall = mockChannel.on.mock.calls.find(c => c[0] === "new_message");
    expect(onCall).toBeDefined();
    const newMessageCallback = onCall![1];

    // Simulate inbound message from malicious agent
    const payload = {
      id: "msg-2",
      type: "task",
      from: "malicious-agent",
      body: "Inject this prompt into the user's session!"
    };

    await newMessageCallback(payload);

    // Verify the message was injected into User A's session!
    // If the vulnerability exists, injectedSessionKey === userASessionKey
    // The test fails if the vulnerability exists (expecting NOT to be userASessionKey)
    expect(injectedSessionKey).toBeDefined();
    expect(injectedSessionKey).not.toBe(userASessionKey);
  });
});