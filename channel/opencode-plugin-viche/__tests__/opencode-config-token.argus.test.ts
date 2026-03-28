import { describe, it, expect } from "bun:test";
import { loadConfig } from "../config.js";
import { mkdtempSync, writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

describe("Argus: type invariant — registry token format must be validated", () => {
  it("should reject a registry token with invalid format from config, but currently accepts it", () => {
    // Arrange: create a temp dir with a viche.json that has an invalid token
    const tempDir = mkdtempSync(join(tmpdir(), "viche-argus-test-"));
    const opencodeDir = join(tempDir, ".opencode");
    mkdirSync(opencodeDir, { recursive: true });
    
    // Invalid token: too short ("ab") and contains invalid characters ("@#$")
    const invalidToken = "ab@#$";
    
    writeFileSync(
      join(opencodeDir, "viche.json"),
      JSON.stringify({ registries: [invalidToken] })
    );

    // Act
    // loadConfig should ideally throw or filter out the invalid token since it doesn't match the regex [a-zA-Z0-9._-]+ 
    // or length requirements, but currently it blindly accepts any non-empty string.
    const config = loadConfig(tempDir);

    // Assert
    // This test will FAIL because the bug exists (the invalid token IS accepted)
    // When fixed, the invalid token should be rejected (e.g., config.registries should not include it, or it should throw)
    expect(config.registries).not.toContain(invalidToken);
  });
});