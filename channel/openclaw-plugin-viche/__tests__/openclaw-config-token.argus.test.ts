import { describe, it, expect } from "bun:test";
import { VicheConfigSchema } from "../types.js";

describe("Argus: type invariant — registry token format must be validated", () => {
  it("should reject a registry token with invalid format, but currently accepts it", () => {
    // The VicheConfigSchema lacks validation for string lengths or character sets for 'registries' array elements.
    // So if a user provides an invalid token, it is passed down to the backend which will fail the registration.
    
    // Arrange: provide an invalid token (too short or special characters)
    const rawConfig = {
      registryUrl: "http://localhost:4000",
      capabilities: ["research"],
      registries: ["ab@#$"] // This is an invalid token format
    };

    // Act
    const result = VicheConfigSchema.parse(rawConfig);

    // Assert: the parse SHOULD fail, so result.success should be false
    // But since the bug exists, result.success is true and it successfully parses it.
    expect(result.success).toBe(false);
  });
});