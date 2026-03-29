---
date: 2026-03-29T12:00:00+02:00
researcher: mnemosyne
git_commit: 930479f4f55acc1259cf0645288b9c22aa0c3e2a
branch: main
repository: viche
topic: "Channel plugin build/lint/test commands"
scope: channel/ directory
query_type: map
tags: [research, plugins, typescript, build-system]
status: complete
confidence: high
sources_scanned:
  files: 23
  thoughts_docs: 0
---

# Research: Channel Plugin Build/Lint/Test Commands

**Date**: 2026-03-29
**Commit**: 930479f4f55acc1259cf0645288b9c22aa0c3e2a
**Branch**: main
**Confidence**: high - All package.json files examined, all config files found

## Query
Research the channel/ plugin directory to understand what build/lint/test commands exist for each plugin.

## Summary
The `channel/` directory contains three TypeScript components: a top-level MCP channel (`viche-channel.ts`), and two plugin subdirectories (`openclaw-plugin-viche/` and `opencode-plugin-viche/`). All use Bun as the runtime. Only `opencode-plugin-viche` has explicit test scripts. Neither plugin has lint configuration (no eslint, biome, or prettier configs found).

## Plugins Overview

| Plugin | Location | Runtime | Has Tests | Has Lint Config | Has TypeCheck |
|--------|----------|---------|-----------|-----------------|---------------|
| viche-channel | `channel/` | Bun | No | No | No (implicit via tsc) |
| openclaw-plugin-viche | `channel/openclaw-plugin-viche/` | npm/node | Yes (manual) | No | Yes (via `tsc`) |
| opencode-plugin-viche | `channel/opencode-plugin-viche/` | Bun | Yes | No | Yes (via `tsc`) |

## Key Entry Points

| File | Symbol | Purpose |
|------|--------|---------|
| `channel/package.json` | - | Top-level MCP channel package |
| `channel/viche-channel.ts` | - | Claude Code MCP channel implementation |
| `channel/openclaw-plugin-viche/package.json` | - | OpenClaw plugin package |
| `channel/opencode-plugin-viche/package.json` | - | OpenCode plugin package |

---

## Plugin 1: viche-channel (Top-Level)

**Location**: `channel/`

### package.json Scripts

| Script | Command | Purpose |
|--------|---------|---------|
| `start` | `bun run viche-channel.ts` | Run the MCP channel server |

### Runtime Requirements
- **Runtime**: Bun (explicit in script)
- **Lock file**: `channel/bun.lock` (Bun lockfile v1)

### Configuration Files
- `channel/package.json` - Package definition
- No `tsconfig.json` at top level

### Dependencies
- `@modelcontextprotocol/sdk`: ^1.0.0
- `phoenix`: ^1.7.0

### Test Files
- **None found**

### Lint Configuration
- **None found** (no eslint, biome, or prettier configs)

---

## Plugin 2: openclaw-plugin-viche

**Location**: `channel/openclaw-plugin-viche/`

### package.json Scripts

| Script | Command | Purpose |
|--------|---------|---------|
| `build` | `tsc` | Compile TypeScript to `dist/` |
| `clean` | `rm -rf dist` | Remove build artifacts |
| `prepublishOnly` | `npm run clean && npm run build` | Pre-publish hook |

### Runtime Requirements
- **Runtime**: npm/node (uses `package-lock.json`)
- **TypeScript**: ^5.9.3

### Configuration Files

| File | Purpose |
|------|---------|
| `channel/openclaw-plugin-viche/package.json` | Package definition |
| `channel/openclaw-plugin-viche/tsconfig.json` | TypeScript config |
| `channel/openclaw-plugin-viche/openclaw.plugin.json` | OpenClaw plugin manifest |

### tsconfig.json Settings
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitOverride": true,
    "outDir": "dist",
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["*.ts"],
  "exclude": ["node_modules", "dist", "*.test.ts", "**/*.test.ts"]
}
```

### Test Files

| File | Type | Framework |
|------|------|-----------|
| `channel/openclaw-plugin-viche/channel-error-recovery.test.ts` | Unit | bun:test |
| `channel/openclaw-plugin-viche/most-recent-leak.argus.test.ts` | Argus | bun:test |
| `channel/openclaw-plugin-viche/viche-reply-ssrf.argus.test.ts` | Argus | bun:test |
| `channel/openclaw-plugin-viche/.argus/correlations-unvalidated-message-id.argus.test.ts` | Argus | bun:test |
| `channel/openclaw-plugin-viche/.argus/discover-response-unvalidated.argus.test.ts` | Argus | bun:test |
| `channel/openclaw-plugin-viche/.argus/inbound-message-unvalidated.argus.test.ts` | Argus | bun:test |

**Note**: Tests exist but no `test` script in package.json. Tests use `bun:test` framework.

### Lint Configuration
- **None found**

### Source Files
- `index.ts` - Plugin entry point
- `service.ts` - Service layer
- `tools.ts` - Tool definitions
- `types.ts` - Type definitions

---

## Plugin 3: opencode-plugin-viche

**Location**: `channel/opencode-plugin-viche/`

### package.json Scripts

| Script | Command | Purpose |
|--------|---------|---------|
| `test` | `bun test __tests__/{config,index,service,tools}.test.ts` | Run unit tests |
| `test:e2e` | `bun test __tests__/e2e.test.ts` | Run E2E tests |
| `test:all` | `bun run test && bun run test:e2e` | Run all tests |
| `build` | `tsc` | Compile TypeScript to `dist/` |
| `prepublishOnly` | `npm run build` | Pre-publish hook |

### Runtime Requirements
- **Runtime**: Bun (uses `bun.lock`, `bun test`)
- **TypeScript**: ^5.9.3

### Configuration Files

| File | Purpose |
|------|---------|
| `channel/opencode-plugin-viche/package.json` | Package definition |
| `channel/opencode-plugin-viche/tsconfig.json` | TypeScript config |
| `channel/opencode-plugin-viche/.gitignore` | Git ignore rules |

### tsconfig.json Settings
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitOverride": true,
    "outDir": "dist",
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["*.ts"],
  "exclude": ["node_modules", "dist"]
}
```

### Test Files

| File | Type | Framework |
|------|------|-----------|
| `channel/opencode-plugin-viche/__tests__/config.test.ts` | Unit | bun:test |
| `channel/opencode-plugin-viche/__tests__/index.test.ts` | Unit | bun:test |
| `channel/opencode-plugin-viche/__tests__/service.test.ts` | Unit | bun:test |
| `channel/opencode-plugin-viche/__tests__/tools.test.ts` | Unit | bun:test |
| `channel/opencode-plugin-viche/__tests__/e2e.test.ts` | E2E | bun:test |
| `channel/opencode-plugin-viche/__tests__/discover-response-schema-validation.argus.test.ts` | Argus | bun:test |
| `channel/opencode-plugin-viche/__tests__/multi-registry-resilience.argus.test.ts` | Argus | bun:test |

### Lint Configuration
- **None found**

### Source Files
- `index.ts` - Plugin entry point
- `config.ts` - Configuration loading
- `service.ts` - Service layer
- `tools.ts` - Tool definitions
- `types.ts` - Type definitions

---

## Shared Configuration

### Top-Level channel/ Directory
- `channel/bun.lock` - Shared Bun lockfile for viche-channel
- `channel/.mcp.json.example` - Example MCP configuration

### Common Patterns
- All plugins use ES2022 target
- All plugins use NodeNext module resolution
- All plugins have strict TypeScript settings
- All tests use `bun:test` framework
- No shared lint configuration exists

---

## Gaps Identified

| Gap | Search Terms Used | Directories Searched |
|-----|-------------------|---------------------|
| No lint config | `.eslintrc*`, `eslint.config.*`, `biome.json`, `.prettierrc*` | `channel/`, `channel/*/` |
| No test script for openclaw-plugin-viche | `test` in package.json scripts | `channel/openclaw-plugin-viche/` |
| No typecheck script (separate from build) | `typecheck`, `type-check` in scripts | All package.json files |
| No jest/vitest config | `jest.config.*`, `vitest.config.*` | `channel/`, `channel/*/` |

---

## Evidence Index

### Code Files
- `channel/package.json` - Top-level package definition
- `channel/viche-channel.ts:1-50` - MCP channel implementation
- `channel/bun.lock:1-30` - Bun lockfile showing dependencies
- `channel/openclaw-plugin-viche/package.json` - OpenClaw plugin package
- `channel/openclaw-plugin-viche/tsconfig.json` - TypeScript config
- `channel/opencode-plugin-viche/package.json` - OpenCode plugin package
- `channel/opencode-plugin-viche/tsconfig.json` - TypeScript config

### Test Files
- `channel/openclaw-plugin-viche/channel-error-recovery.test.ts:1-30` - Uses bun:test
- `channel/opencode-plugin-viche/__tests__/config.test.ts:1-30` - Uses bun:test

---

## Handoff Inputs

**If adding plugin validation to mix precommit** (for @vulkanus):

**Available Commands per Plugin:**

| Plugin | Build | Test | Typecheck |
|--------|-------|------|-----------|
| viche-channel | N/A (single file) | N/A | `bun --bun tsc --noEmit` (needs tsconfig) |
| openclaw-plugin-viche | `npm run build` | `bun test *.test.ts` (manual) | `npm run build` (tsc) |
| opencode-plugin-viche | `bun run build` | `bun run test` | `bun run build` (tsc) |

**Suggested Validation Commands:**
1. For `opencode-plugin-viche`: `cd channel/opencode-plugin-viche && bun run build && bun run test`
2. For `openclaw-plugin-viche`: `cd channel/openclaw-plugin-viche && npm run build && bun test *.test.ts .argus/*.test.ts`
3. For `viche-channel`: Would need a tsconfig.json to enable `tsc --noEmit`

**Open Questions:**
- Should lint be added? (Currently no lint config exists)
- Should openclaw-plugin-viche get a `test` script in package.json?
- Should viche-channel.ts get its own tsconfig.json for type checking?
