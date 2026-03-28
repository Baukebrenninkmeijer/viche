import { describe, it, expect } from "bun:test";
import { registerVicheTools } from "../tools.js";
import { TypeCompiler } from "@sinclair/typebox/compiler";

describe("Argus: type invariant — viche_send 'to' parameter must be a valid UUID", () => {
  it("should enforce UUID format for 'to' parameter, but currently accepts any string", () => {
    // We will intercept the schema registration by mocking the context
    let registeredSchema: any;
    
    const apiMock: any = {
      registerTool: (schema: any) => {
        if (schema.name === "viche_send") {
          registeredSchema = schema.parameters;
        }
      }
    };
    
    registerVicheTools(apiMock, { registryUrl: "http://localhost:4000" }, { agentId: "123" } as any);

    // Act & Assert
    // registeredSchema is a TypeBox schema. We can compile it to validate.
    const compiler = TypeCompiler.Compile(registeredSchema);
    
    const invalidInput = {
      to: "not-a-uuid", // This should be rejected
      body: "Hello"
    };

    // The validation SHOULD fail, but since the bug exists, it accepts it.
    // So compiler.Check(invalidInput) returns true.
    expect(compiler.Check(invalidInput)).toBe(false);
  });
});