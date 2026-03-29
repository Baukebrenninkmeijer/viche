---
date: 2026-03-29T12:00:00+02:00
researcher: mnemosyne
git_commit: 930479f
branch: main
repository: viche
topic: "Project setup requirements and development workflow for Contributing guide"
scope: Full project including Elixir backend and TypeScript plugins
query_type: map
tags: [research, contributing, setup, development-workflow]
status: complete
confidence: high
sources_scanned:
  files: 18
  thoughts_docs: 0
---

# Research: Project Setup Requirements and Development Workflow

**Date**: 2026-03-29
**Commit**: 930479f
**Branch**: main
**Confidence**: high - All information sourced directly from project configuration files and CI workflow

## Query
Research the Viche project setup requirements and development workflow details needed for a Contributing guide in the README.

## Summary
Viche is an Elixir/Phoenix 1.8 application requiring Elixir 1.19+, OTP 28, and PostgreSQL 16. The project uses `mix setup` for one-command initialization, `mix precommit` as the quality gate, and provides docker-compose for PostgreSQL. Plugin development in `channel/` requires Bun runtime for TypeScript.

## Key Entry Points

| File | Symbol | Purpose |
|------|--------|---------|
| `mix.exs:4-17` | `project/0` | Project configuration including Elixir version requirement |
| `mix.exs:82-103` | `aliases/0` | Mix aliases including `setup` and `precommit` |
| `.github/workflows/ci.yml:41-45` | CI setup | Exact Elixir/OTP versions used in CI |
| `config/dev.exs:4-11` | Repo config | Database configuration for development |
| `config/test.exs:8-14` | Repo config | Database configuration for tests |
| `docker-compose.yml:1-14` | PostgreSQL service | Docker setup for local PostgreSQL |
| `channel/package.json:1-13` | MCP channel | Bun/TypeScript dependencies for Claude Code plugin |

## Prerequisites

### Required Versions (from CI and mix.exs)

| Dependency | Version | Source |
|------------|---------|--------|
| Elixir | ~> 1.15 (CI uses 1.19) | `mix.exs:8`, `.github/workflows/ci.yml:44` |
| Erlang/OTP | 28 | `.github/workflows/ci.yml:45` |
| PostgreSQL | 16 | `.github/workflows/ci.yml:20`, `docker-compose.yml:3` |
| Bun | Latest (for plugins) | `channel/package.json:7` |

### Runtime Elixir Version (current environment)
- Elixir: 1.19.2
- OTP: 28

### Version Management
**Gap identified**: No `.tool-versions`, `.elixir-version`, or `.erlang-version` files found in project root. Version management relies on CI configuration and developer environment.

## Database Configuration

### Development (`config/dev.exs:4-11`)
```elixir
config :viche, Viche.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "viche_dev",
  pool_size: 10
```

### Test (`config/test.exs:8-14`)
```elixir
config :viche, Viche.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "viche_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2
```

### Docker Compose (`docker-compose.yml`)
Provides PostgreSQL 16 Alpine with default credentials:
- User: `postgres`
- Password: `postgres`
- Database: `viche_dev`
- Port: `5432`

## Setup Commands

### Full Setup (from `mix.exs:84`)
```bash
mix setup
```
This alias runs:
1. `deps.get` - Install dependencies
2. `ecto.setup` - Create database, run migrations, seed data
3. `assets.setup` - Install Tailwind and esbuild if missing
4. `assets.build` - Compile assets

### Database Setup (from `mix.exs:85`)
```bash
mix ecto.setup
```
Runs:
1. `ecto.create` - Create database
2. `ecto.migrate` - Run migrations
3. `run priv/repo/seeds.exs` - Seed data (currently empty placeholder)

### Migrations Present
| Migration | Purpose |
|-----------|---------|
| `20260329105819_create_users.exs` | Creates users table with citext extension |
| `20260329105820_create_auth_tokens.exs` | Creates auth_tokens table |

**Note from AGENTS.md**: "There are **no Ecto schemas or migrations** [for agents]. `Agent` and `Message` are plain structs. All state lives in GenServer processes." The migrations above are for user authentication, not agent state.

## Running the Server

```bash
iex -S mix phx.server
```
Server runs at `http://localhost:4000` (configurable via `PORT` env var per `config/runtime.exs:23`).

## Running Tests

### Full Test Suite (from `mix.exs:87`)
```bash
mix test
```
This alias runs:
1. `ecto.create --quiet` - Ensure test database exists
2. `ecto.migrate --quiet` - Run migrations
3. `test` - Execute tests

### Individual Test File
```bash
mix test test/path/to/test.exs
```

### Failed Tests Only
```bash
mix test --failed
```

### Test Partitioning (CI)
Environment variable `MIX_TEST_PARTITION` supports parallel test execution in CI.

## Quality Gate: Precommit

### Command (from `mix.exs:95-102`)
```bash
mix precommit
```

### Steps Executed
1. `compile --warnings-as-errors` - Compilation with strict warnings
2. `deps.unlock --unused` - Remove unused dependencies
3. `format` - Code formatting
4. `credo --strict` - Static analysis
5. `test` - Test suite
6. `dialyzer` - Type checking

**Note**: Runs in test environment per `mix.exs:31`: `preferred_envs: [precommit: :test]`

## Environment Variables

### Development (none required)
Default configuration in `config/dev.exs` works without environment variables.

### Production (`config/runtime.exs`)
| Variable | Required | Purpose |
|----------|----------|---------|
| `DATABASE_URL` | Yes | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Yes | Phoenix secret key |
| `PHX_HOST` | No | Host for URL generation (default: "example.com") |
| `PHX_SERVER` | No | Enable server (set to "true" for releases) |
| `PORT` | No | HTTP port (default: 4000) |
| `POOL_SIZE` | No | Database pool size (default: 10) |
| `ECTO_IPV6` | No | Enable IPv6 for database |
| `DNS_CLUSTER_QUERY` | No | DNS cluster configuration |

### Plugin Environment Variables (from `.mcp.json` and AGENTS.md)
| Variable | Purpose |
|----------|---------|
| `VICHE_REGISTRY_URL` | Registry base URL (default: `http://localhost:4000`) |
| `VICHE_CAPABILITIES` | Comma-separated capabilities |
| `VICHE_AGENT_NAME` | Human-readable agent name |
| `VICHE_DESCRIPTION` | Agent description |
| `VICHE_REGISTRY_TOKEN` | Comma-separated registry tokens |

## Plugin Development (channel/ directory)

### Directory Structure
```
channel/
├── viche-channel.ts          # Claude Code MCP channel
├── package.json              # Root dependencies (Bun)
├── bun.lock
├── opencode-plugin-viche/    # OpenCode plugin
│   ├── package.json
│   ├── index.ts
│   └── ...
└── openclaw-plugin-viche/    # OpenClaw plugin
    ├── package.json
    ├── index.ts
    └── ...
```

### Root Channel Setup (`channel/package.json`)
```bash
cd channel
bun install
```

Dependencies:
- `@modelcontextprotocol/sdk: ^1.0.0`
- `phoenix: ^1.7.0`

### OpenCode Plugin (`channel/opencode-plugin-viche/package.json`)
```bash
cd channel/opencode-plugin-viche
bun install
bun run build  # TypeScript compilation
bun run test   # Run tests
```

Dependencies:
- `phoenix: ^1.8.5`
- `zod: ^4.0.0`

Peer dependencies:
- `@opencode-ai/plugin: >=0.0.1`
- `@opencode-ai/sdk: >=0.0.1`

### OpenClaw Plugin (`channel/openclaw-plugin-viche/package.json`)
```bash
cd channel/openclaw-plugin-viche
npm install
npm run build  # TypeScript compilation
```

Dependencies:
- `@sinclair/typebox: ^0.34.48`
- `phoenix: ^1.8.5`

Peer dependencies:
- `openclaw: >=2026.2.1`

### Running Claude Code with Viche Channel
```bash
# Start Phoenix server first
iex -S mix phx.server

# In another terminal, launch Claude Code with Viche
claude --dangerously-load-development-channels server:viche --dangerously-skip-permissions
```

## E2E Testing Scripts

### `scripts/e2e-curl-test.sh`
Validates all 5 REST endpoints work together:
```bash
VICHE=http://localhost:4000 ./scripts/e2e-curl-test.sh
```

Tests: register → discover → send → inbox (consume) → inbox (empty) → reply → inbox (reply)

## Git Hooks

### Pre-commit (`.githooks/pre-commit`)
Delegates to `bd hook pre-commit` (beads task management system). If `bd` is not installed, hook is skipped with a warning.

## Asset Build Requirements

### Tailwind (`config/config.exs:45-53`)
- Version: 4.1.12
- Input: `assets/css/app.css`
- Output: `priv/static/assets/css/app.css`

### esbuild (`config/config.exs:35-42`)
- Version: 0.25.4
- Input: `js/app.js`
- Output: `priv/static/assets/js/`

Assets are automatically installed via `mix assets.setup` (part of `mix setup`).

## Gaps Identified

| Gap | Search Terms Used | Notes |
|-----|-------------------|-------|
| No version management files | `.tool-versions`, `.elixir-version`, `.erlang-version` | Developers must manually ensure correct versions |
| No explicit Node.js requirement | `node`, `npm` | OpenClaw plugin uses npm, but version not specified |

## Evidence Index

### Code Files
- `mix.exs:1-105` - Project configuration, aliases, dependencies
- `config/config.exs:1-65` - Base configuration, asset versions
- `config/dev.exs:1-92` - Development configuration
- `config/test.exs:1-44` - Test configuration
- `config/runtime.exs:1-119` - Runtime/production configuration
- `docker-compose.yml:1-14` - PostgreSQL Docker setup
- `.github/workflows/ci.yml:1-70` - CI workflow with exact versions
- `channel/package.json:1-13` - MCP channel dependencies
- `channel/opencode-plugin-viche/package.json:1-63` - OpenCode plugin config
- `channel/openclaw-plugin-viche/package.json:1-61` - OpenClaw plugin config
- `.mcp.json:1-14` - Claude Code MCP configuration
- `.githooks/pre-commit:1-24` - Git pre-commit hook
- `scripts/e2e-curl-test.sh:1-183` - E2E test script
- `priv/repo/seeds.exs:1-11` - Empty seed file
- `priv/repo/migrations/20260329105819_create_users.exs:1-17` - Users migration
- `priv/repo/migrations/20260329105820_create_auth_tokens.exs:1-20` - Auth tokens migration

### Documentation
- `AGENTS.md` - Architecture guide, conventions, developer workflows
- `README.md:133-138` - Self-hosting quick start

---

## Handoff Inputs

**If documentation needed** (for README Contributing section):

**Prerequisites to document**:
- Elixir 1.19+ (CI version)
- Erlang/OTP 28
- PostgreSQL 16
- Bun (for plugin development)

**Setup sequence**:
1. Clone repository
2. Start PostgreSQL (via docker-compose or local install)
3. Run `mix setup`
4. Run `iex -S mix phx.server`

**Quality gate**: `mix precommit` (runs compile, format, credo, test, dialyzer)

**Test commands**:
- Full suite: `mix test`
- Single file: `mix test test/path/to/file.exs`
- Failed only: `mix test --failed`

**Plugin development**:
- Requires Bun runtime
- Each plugin has its own `package.json`
- Build with `bun run build` or `npm run build`
