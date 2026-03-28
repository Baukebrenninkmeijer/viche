import { describe, it, expect } from "bun:test";
import { createVicheTools } from "../tools.js";

describe("Argus: type invariant — viche_send 'to' parameter must be a valid UUID", () => {
  it("should enforce UUID format for 'to' parameter, but currently accepts any string", () => {
    // Arrange: Create the tools
    const tools = createVicheTools(
      { registryUrl: "http://localhost:4000", registries: ["token"] },
      { agentId: "agent-id", socket: {}, channel: {} },
      async () => ({ agentId: "agent-id", socket: {}, channel: {} })
    );

    const vicheSend = tools["viche_send"];
    
    // Act & Assert
    // The Zod schema for viche_send.args.to should reject non-UUID strings.
    // In zod, we can parse an object against the schema.
    const argsSchema = require("zod").object(vicheSend.args);
    
    // An invalid ID like "12345" (not UUID)
    const invalidInput = {
      to: "12345", 
      body: "Hello"
    };

    // This will FAIL if the bug exists, because the schema will successfully parse the invalid input
    // and safeParse().success will be true. We EXPECT it to throw or be unsuccessful.
    const result = argsSchema.safeParse(invalidInput);
    expect(result.success).toBe(false);
  });
});