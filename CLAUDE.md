# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **⚠️ TWO REPOS** — This project spans two git repositories. Always commit and push both when making changes.
> - `cortex_community` (this repo) → `github.com/chinostroza/cortex-community`
> - `cortex_core` → `../cortex-core/cortex_core` → `github.com/chinostroza/cortex-core`

## Project Overview

CortexCommunity is an open-source AI gateway built with Phoenix Framework that provides a unified interface to multiple AI providers (OpenAI, Anthropic, Google Gemini, Groq, Cohere, xAI) plus local AI support via Ollama.

## Common Development Commands

```bash
# Setup & Development
mix setup          # Install deps + setup assets
mix server         # Start Phoenix server (alias for phx.server)

# Testing & Quality
mix test           # Run tests
mix test test/path/to/test.exs  # Run specific test file
mix test.coverage  # Run tests with coverage
mix quality        # Format code and run credo
mix format         # Format code only
mix credo --strict # Run linter only

# Assets (for frontend changes)
mix assets.build   # Build CSS and JS
mix assets.deploy  # Build minified for production

# Release
mix release        # Build production release

# Docker
docker-compose up  # Start app with Ollama
```

## Architecture Overview

### Core Components

1. **Cortex Core Integration** (`cortex_core ~> 1.0.2`): The underlying AI routing engine that handles:
   - Provider management (OpenAI, Anthropic, Google, etc.)
   - Worker pool strategies (local_first, round_robin, least_used, random)
   - Health checks and failover
   - API key rotation

2. **Phoenix Web Layer** (`lib/cortex_community_web/`):
   - **Controllers**: Handle HTTP endpoints
     - `ChatController`: Main `/api/chat` endpoint with SSE streaming
     - `CompletionsController`: OpenAI-compatible `/api/completions`
     - `HealthController`: Health checks and worker status
     - `StatsController`: Usage statistics and metrics
   - **Router**: Defines API routes under `/api` scope

3. **Application Core** (`lib/cortex_community/`):
   - `Application`: OTP supervisor managing:
     - StatsCollector (GenServer for in-memory metrics)
     - Cortex Core supervisor
   - `StatsCollector`: Tracks request metrics, token usage, and provider statistics

### Key API Endpoints

- `/api/chat` - Main chat endpoint with SSE streaming support
- `/api/completions` - OpenAI-compatible completions endpoint
- `/api/health` - Basic health check
- `/api/health/workers` - Detailed worker status
- `/api/stats` - Request statistics
- `/api/stats/providers` - Per-provider metrics

### Environment Configuration

Key environment variables:
- `CORTEX_*` - Cortex Core configuration (worker pools, strategies, etc.)
- Provider API keys: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`, etc.
- `PORT` - Server port (default: 4000)
- `SECRET_KEY_BASE` - Phoenix secret key

### Testing Approach

- Tests are in `test/` directory
- Run specific tests with `mix test test/file_test.exs`
- Use `Phoenix.ConnTest` for controller tests
- Test SSE endpoints by checking response headers and chunks

### Development Guidelines

1. **Phoenix Conventions**: 
   - Follow standard Phoenix patterns
   - Use `Req` library for HTTP requests (already included)
   - Controllers return conn, not JSON directly

2. **Cortex Core Usage**:
   - Worker management is handled by Cortex Core
   - Use `Cortex.chat/2` for AI interactions
   - Health checks run automatically based on config

3. **Error Handling**:
   - Controllers handle Cortex errors gracefully
   - SSE streams include error events
   - Stats collector tracks failures

4. **Code Quality**:
   - Run `mix quality` before commits
   - Follow formatter rules in `.formatter.exs`
   - Credo enforces code standards
   - Run `/certify-phoenix-api` skill after significant changes

### Testing Workflow (TDD + Mox)

**Stack**: Mox for mock-based unit tests, `mix coveralls` for coverage (minimum 80%)

**Architecture**:
- `CortexCore.Behaviour` (in cortex_core) + `CortexCore.Mock` — mocks all AI provider calls
- `CortexCommunity.UsersBehaviour` + `CortexCommunity.Users.Mock` — mocks auth/user lookup
- Module injection: `@cortex_core Application.compile_env(:cortex_community, :cortex_core, CortexCore)` — in all controllers and plugs
- `test/support/conn_case.ex` exports `user_fixture/0` and `with_auth/1` helpers
- `coveralls.json` excludes OAuth clients, Mix tasks, Ecto schemas, Phoenix boilerplate

**Rules**:
1. **401 tests** — no mock setup needed (auth fails before mock is called)
2. **400/200 tests** — `stub(Users.Mock, :authenticate_by_api_key, ...)` in setup block
3. **Behavior verification** — use `expect/3` (must be called once); use `stub/3` for setup
4. Auth plug: `"Token xyz"` fails before DB; `"Bearer <anything>"` triggers Users.Mock lookup
5. SSE error responses keep `text/event-stream` content-type — use `conn.resp_body` + `Jason.decode/1`
6. `StatsCollector` tests: call `reset_stats()` in setup; GenServer.cast/call order guarantees consistency
7. cortex_core tests live in `cortex-core/cortex_core/test/`; run from cortex_community with `mix compile` first

**Coverage exclusions** (in `coveralls.json`): OAuth/CLI clients, Mix tasks, Ecto schemas, Phoenix boilerplate

### Endpoint Map (all verified working)

| Endpoint | Auth | Notes |
|----------|------|-------|
| `POST /api/chat` | ✅ | SSE streaming |
| `POST /api/completions` | ✅ | OpenAI-compatible alias |
| `POST /api/search` | ✅ | tavily-primary, pubmed-primary |
| `POST /api/tools` | ✅ | function calling, requires explicit `provider` |
| `GET /api/models` | ✅ | lists all workers |
| `GET /api/health` | ❌ | public |
| `GET /api/health/workers` | ❌ | public |
| `GET /api/stats` | ❌ | public |

| `GET /api/health/detailed` | ❌ | public |
| `GET /api/stats/providers` | ❌ | public |
| `GET /docs` | ❌ | public HTML |

Groq tool calling: must specify `model: "llama-3.3-70b-versatile"` (default returns empty [])

### E2E Integration Tests (Playwright)

Tests que validan el stack completo: assistant UI ↔ cortex gateway.
Viven en: `../assistant/e2e/` (repo del assistant)

**Prerequisito**: Cortex corriendo en `:4000`. El assistant lo arranca Playwright automáticamente en `:4001`.

**Correr**:
```bash
cd /ruta/al/assistant/e2e
npm run test:e2e -- --project integration   # solo integración (Chromium, ~2 min)
npm run test:e2e                            # suite completa (todos los browsers)
```

**Tests** (`e2e/tests/cortex-integration.spec.ts`):
- INTEG-001..005: Chat round-trip, streaming, stop, estado limpio, respuesta no vacía
- INTEG-006..007: Nueva conversación, contexto multi-turno
- INTEG-008..009: Cortex health API (estructura + workers)
- INTEG-010: Markdown rendering (bloques de código)

**Cuándo correr**: Después de modificar cortex↔assistant (streaming, error handling, health endpoints).