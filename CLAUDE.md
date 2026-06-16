# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **⚠️ TWO REPOS** — This project spans two git repositories. Always commit and push both when making changes.
> - `cortex_community` (this repo) → `github.com/chinostroza/cortex-community`
> - `cortex_core` → `../cortex-core/cortex_core` → `github.com/chinostroza/cortex-core`

## Project Overview

**Cortex Community** is an open-source AI gateway built with Phoenix Framework that provides a unified interface to multiple AI providers:

**Providers:** OpenAI, Anthropic, Google Gemini, Groq, Cohere, xAI, Ollama, **Qwen**

**Key Features:**
- OAuth workers for Claude Pro Max (Claude Code CLI) and Qwen Code
- OpenAI-compatible API (drop-in replacement)
- Intelligent load balancing with multiple strategies
- Automatic failover and health monitoring
- Model discovery and ranking by task type (chat, coding, reasoning, tools, long_context, fast)
- Server-Sent Events for real-time streaming
- Function calling with capability-based auto-routing

## Common Development Commands

```bash
# Setup & Development
mix setup          # Install deps + setup assets + DB
mix server         # Start Phoenix server at :4000 (alias for phx.server)

# Database
mix ecto.create    # Create database
mix ecto.migrate   # Run migrations
mix ecto.reset     # Drop + create + migrate

# Interactive Setup
mix cortex.setup   # Wizard to configure providers and API keys
mix cortex.keygen <name>  # Generate persistent API key for a project

# Testing & Quality
mix test           # Run tests (110 tests in cortex_community)
mix test test/path/to/test.exs  # Run specific test file
mix test --failed  # Run last failed tests
mix test.coverage  # Run tests with coverage
mix quality        # Format + credo + sobelow
mix format         # Format code only
mix credo --strict # Run linter only
mix sobelow --skip # Security audit

# Assets (for frontend changes)
mix assets.build   # Build CSS and JS
mix assets.deploy  # Build minified for production

# Release
MIX_ENV=prod mix release  # Build production release

# Docker
docker-compose up  # Start app with Ollama
```

## Architecture Overview

### Two-Repo Structure

```
cortex_community/          # Phoenix app (web layer, auth, OAuth readers)
├── lib/cortex_community/  # Domain layer
│   ├── auth/              # OAuth credential readers
│   ├── clients/           # HTTP clients for external APIs
│   ├── workers/           # OAuth workers (Anthropic, Qwen)
│   ├── model_discovery/   # Auto model discovery & ranking
│   └── ...                # Users, credentials, stats
│
└── cortex_core/           # Pure Elixir library (AI engine)
    └── Workers.Pool       # GenServer pool + capabilities
```

### Core Components

1. **Cortex Core Integration** (`cortex_core` - path dependency):
   - `CortexCore.Workers.Pool` (GenServer) - Worker registry + capabilities
   - `CortexCore.chat/2` - Main entry point with failover
   - Worker adapters for each provider
   - Health check system

2. **Phoenix Web Layer** (`lib/cortex_community_web/`):
   - **Controllers**:
     - `ChatController` - `/api/chat`, `/api/completions` (SSE streaming, OAuth support)
     - `ToolsController` - `/api/tools` (function calling, capability validation)
     - `SearchController` - `/api/search` (web search with multiple providers)
     - `ModelsController` - `/api/models` (workers + capabilities + context windows)
     - `HealthController` - `/api/health*` (health checks + recommendations)
     - `StatsController` - `/api/stats*` (usage metrics)
     - `DocsController` - `/docs*` (documentation portal)
     - `PageController` - `/` (HTML dashboard)
   - **Plugs**:
     - `AuthenticateApiKey` - API key authentication
     - `RequestLogger` - Request logging with duration

3. **OAuth Workers** (local credentials):
   - `AnthropicOAuthWorker` - Claude Pro Max via Claude Code CLI
   - `QwenOAuthWorker` - Qwen Code via OAuth tokens

4. **Model Discovery** (`lib/cortex_community/model_discovery/`):
   - `ModelSelector` (GenServer) - Orchestrates discovery + ranking
   - `ModelInfo` - Context window lookup
   - `ProviderModel` / `ModelRanking` - DB schemas

5. **Application Core** (`lib/cortex_community/`):
   - `Application` - OTP supervisor
   - `StatsCollector` (GenServer) - Usage statistics
   - `Users` / `Credentials` - User management + encrypted storage

### Worker Capabilities

| Worker | Capabilities | Priority | Source |
|--------|-------------|----------|--------|
| `anthropic-primary` | `[:chat, :tools, :reasoning]` | 1 | API key |
| `anthropic-oauth-local` | `[:chat, :tools, :reasoning]` | 5 | OAuth (Claude CLI) |
| `gemini-primary` | `[:chat, :tools, :long_context, :vision]` | 2 | API key |
| `groq-primary` | `[:chat, :tools, :fast]` | 3 | API key |
| `openai-primary` | `[:chat, :tools, :vision]` | 1 | API key |
| `qwen-oauth-local` | `[:chat, :tools, :vision, :fast]` | 8 | OAuth (Qwen Code) |
| `cohere-primary` | `[:chat]` | 4 | API key |
| `xai-primary` | `[:chat]` | 4 | API key |
| `ollama-local` | `[:chat]` | 5 | Local |
| search workers | `[:search]` | - | API key |

**Priority:** Higher = more preferred (OAuth workers have priority 5-8 for free tier).

### Auto-Routing

- `/api/tools` sin `provider` → auto-routing a workers con `:tools` capability
- `/api/tools` con provider sin `:tools` → 400 "does not support tool calling"
- `/api/chat` sin `provider` → usa `CortexCore.chat/2` con failover automático

## API Endpoints

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `POST /api/chat` | POST | ✅ | SSE streaming, failover, OAuth support |
| `POST /api/completions` | POST | ✅ | OpenAI-compatible (same handler as /chat) |
| `POST /api/tools` | POST | ✅ | Function calling, capability validation |
| `POST /api/search` | POST | ✅ | Web search (Tavily, Serper, Brave, etc.) |
| `GET /api/models` | GET | ✅ | Workers + capabilities + context windows |
| `GET /api/health` | GET | ❌ | Basic health check |
| `GET /api/health/workers` | GET | ❌ | Detailed worker status |
| `GET /api/health/detailed` | GET | ❌ | Full system + recommendations by task type |
| `GET /api/stats` | GET | ✅ | Usage statistics |
| `GET /api/stats/providers` | GET | ✅ | Per-provider statistics |
| `GET /` | GET | ❌ | HTML dashboard |
| `GET /docs` | GET | ❌ | Documentation portal |
| `GET /docs/api` | GET | ❌ | API reference |
| `GET /docs/quickstart` | GET | ❌ | Quick start guide |

## Authentication

### API Keys

**Format:** `ctx_` + base62 encoded (ej: `ctx_AVnjkXxaIgx1MVQaTQ1dGlovAzdqZNAM`)

**Header:** `Authorization: Bearer ctx_...`

**Default key (dev):** Generated on startup, stored in `/tmp/cortex_api_key.txt`

### OAuth Credentials

| Provider | Credentials File | Worker Name |
|----------|-----------------|-------------|
| Anthropic (Claude CLI) | `~/.claude/.credentials.json` | `anthropic-oauth-local` |
| Qwen Code | `~/.qwen/oauth_creds.json` | `qwen-oauth-local` |

**Auth Flow (ChatController):**
1. Sin auth → server API keys
2. Con auth → user credentials first
3. OAuth falla → fallback a server pool (Gemini/Groq)

## Environment Variables

```bash
# API Keys (comma-separated for multiple)
OPENAI_API_KEYS=sk-...
ANTHROPIC_API_KEYS=sk-ant-...
GOOGLE_API_KEYS=...
GROQ_API_KEYS=gsk_...
COHERE_API_KEYS=...
XAI_API_KEYS=xai-...

# Search APIs
TAVILY_API_KEY=...
SERPER_API_KEY=...
BRAVE_API_KEY=...

# Server
PORT=4000
SECRET_KEY_BASE=...
WORKER_POOL_STRATEGY=local_first  # local_first, round_robin, least_used, random
HEALTH_CHECK_INTERVAL=30000
```

## Testing Workflow (TDD + Mox)

**Stack:** Mox for mock-based unit tests, `mix coveralls` for coverage (minimum 80%)

**Architecture:**
- `CortexCore.Behaviour` + `CortexCore.Mock` — mocks all AI provider calls
- `CortexCommunity.UsersBehaviour` + `CortexCommunity.Users.Mock` — mocks auth/user lookup
- Module injection: `@cortex_core Application.compile_env(:cortex_community, :cortex_core, CortexCore)`
- `test/support/conn_case.ex` exports `user_fixture/0` and `with_auth/1` helpers
- `coveralls.json` excludes OAuth clients, Mix tasks, Ecto schemas, Phoenix boilerplate

**Rules:**
1. **401 tests** — no mock setup needed (auth fails before mock is called)
2. **400/200 tests** — `stub(Users.Mock, :authenticate_by_api_key, ...)` in setup block
3. **Behavior verification** — use `expect/3` (must be called once); use `stub/3` for setup
4. Auth plug: `"Token xyz"` fails before DB; `"Bearer <anything>"` triggers Users.Mock lookup
5. SSE error responses keep `text/event-stream` content-type — use `conn.resp_body` + `Jason.decode/1`
6. `StatsCollector` tests: call `reset_stats()` in setup; GenServer.cast/call order guarantees consistency
7. cortex_core tests live in `cortex-core/cortex_core/test/`; run from cortex_community with `mix compile` first

**Coverage exclusions** (in `coveralls.json`): OAuth/CLI clients, Mix tasks, Ecto schemas, Phoenix boilerplate

## OAuth Testing (iex -S mix)

```elixir
# Claude OAuth
CortexCommunity.Auth.ClaudeCliReader.read_credentials()
CortexCommunity.Auth.ClaudeCliReader.valid?(creds)

{:ok, creds} = CortexCommunity.Auth.ClaudeCliReader.read_credentials()
{:ok, stream} = CortexCommunity.Clients.ClaudeOAuthClient.chat(
  [%{"role" => "user", "content" => "hola"}],
  creds
)
stream |> Enum.join("") |> IO.puts()

# Qwen OAuth
CortexCommunity.Auth.QwenCredentialReader.read_credentials()
CortexCommunity.Auth.QwenCredentialReader.valid?(creds)

# Model Discovery
CortexCommunity.ModelSelector.get_rankings()
CortexCommunity.ModelSelector.best_worker_for(:coding)

# Stats
CortexCommunity.StatsCollector.get_stats()
CortexCommunity.StatsCollector.get_provider_stats()

# Pool Capabilities
CortexCore.Workers.Pool.get_capabilities("groq-primary")
CortexCore.Workers.Pool.get_capabilities("anthropic-oauth-local")
```

## Database

**Schemas (6):**
- `cortex_users`
- `cortex_api_keys`
- `user_credentials` (encrypted AES-256-GCM)
- `provider_models` (discovered models per worker)
- `model_rankings` (rankings by task type)

**Migrations (7):** All in `priv/repo/migrations/`

## Code Quality

**Pre-commit:**
```bash
mix format
mix credo --strict
mix sobelow --skip
mix test
```

**Or use alias:**
```bash
mix quality  # format + credo + sobelow
```

## Development Guidelines

1. **Phoenix Conventions**:
   - Follow standard Phoenix patterns
   - Use `Req` library for HTTP requests (already included)
   - Controllers return conn, not JSON directly
   - LiveView templates start with `<Layouts.app flash={@flash} ...>`

2. **Cortex Core Usage**:
   - Worker management handled by `CortexCore.Workers.Pool`
   - Use `CortexCore.chat/2` for AI interactions
   - Capabilities set via `Pool.set_capabilities/3`
   - Health checks run automatically (60s tick, 5min full check)

3. **Error Handling**:
   - Controllers handle Cortex errors gracefully
   - SSE streams include error events
   - StatsCollector tracks failures
   - Tool calling returns specific error codes (400, 404, 429, 502, 503)

4. **OAuth Workers**:
   - Credentials read from local files (Claude CLI, Qwen Code)
   - Higher priority than API key workers (free tier)
   - Expiration checked on each request
   - Fallback to server pool if OAuth fails

5. **Model Discovery**:
   - Auto-discovers models on startup (3s delay)
   - Rankings generated via LLM evaluation
   - Re-discovers every 24h
   - Health check rotates unhealthy models

## Known Limitations / Pending

| Module | Status | Notes |
|--------|--------|-------|
| `ClaudeWebClient.chat/3` | ⚠️ Not implemented | Returns `{:error, :not_yet_implemented}` |
| `DashboardLive` | ⚠️ Not implemented | Route defined but no LiveView exists |
| OAuth token refresh | ⚠️ Not implemented | `refresh_token/1` returns `{:error, :not_implemented}` |

## E2E Integration Tests (Playwright)

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

## Certification

After significant changes, run the certification pipeline:

```bash
# Use the certify-phoenix-api skill
```

This runs: format → credo → dialyzer → sobelow → coveralls → deps.audit
