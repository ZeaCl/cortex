# Cortex Community — Qwen Code Context

## Proyecto

Gateway de AI unificado en Phoenix/Elixir que enruta requests a múltiples providers
(Anthropic, Gemini, Groq, OpenAI, Cohere, xAI, Ollama, Qwen) más OAuth workers locales.

**Dos repos:**
| Repo | Path |
|------|------|
| `cortex_community` | `/Users/dev/Documents/zea/cortex/cortex_community` |
| `cortex_core` | `/Users/dev/Documents/zea/cortex/cortex-core/cortex_core` |

- `cortex_core` = librería pura (workers, dispatcher, adapters, Pool). NO Phoenix/Ecto.
- `cortex_community` = Phoenix app (controllers, auth, web, OAuth readers).
- Compilar: `mix compile` desde cortex_community. Servidor: `mix server` en `:4000`.
- API key local: `ctx_AVnjkXxaIgx1MVQaTQ1dGlovAzdqZNAM`

---

## Arquitectura del Pool

```
CortexCore.Workers.Pool (GenServer)
  state.workers      ← Registry (workers registrados)
  state.capabilities ← %{"groq-primary" => [:chat, :tools, :fast], ...}
  state.health_status ← %{"groq-primary" => :available, ...}

Pool.stream_completion(messages, opts)      → chat con failover
Pool.call_with_tools(messages, tools, opts) → tools con capability filter
Pool.call(service_type, params, opts)       → search/embeddings
```

---

## Workers Registrados

### LLM Workers (API Keys)

| Worker | Capabilities | Priority | Modelo Default |
|--------|-------------|----------|----------------|
| `anthropic-primary` | `[:chat, :tools, :reasoning]` | 1 | `claude-sonnet-4-5-20250929` |
| `gemini-primary` | `[:chat, :tools, :long_context, :vision]` | 2 | `gemini-2.5-flash` |
| `gemini-pro-25-primary` | `[:chat, :tools, :long_context, :vision]` | 2 | `gemini-2.5-pro` |
| `groq-primary` | `[:chat, :tools, :fast]` | 3 | `llama-3.3-70b-versatile` |
| `openai-primary` | `[:chat, :tools, :vision]` | 1 | `gpt-4o` |
| `cohere-primary` | `[:chat]` | 4 | `command-r-plus` |
| `xai-primary` | `[:chat]` | 4 | `grok-2-latest` |
| `ollama-local` | `[:chat]` | 5 | `llama3.2` |

### OAuth Workers (Local Credentials)

| Worker | Credentials | Capabilities | Priority | Modelo |
|--------|------------|-------------|----------|--------|
| `anthropic-oauth-local` | `~/.claude/.credentials.json` | `[:chat, :tools, :reasoning]` | 5 | `claude-sonnet-4-5-20250929` |
| `qwen-oauth-local` | `~/.qwen/oauth_creds.json` | `[:chat, :tools, :vision, :fast]` | 8 | `coder-model` |

**Nota:** OAuth workers tienen prioridad alta (free tier, sin costo de API).

### Search Workers

| Worker | Capability | API Key Env |
|--------|-----------|-------------|
| `tavily-primary` | `[:search]` | `TAVILY_API_KEY` |
| `serper-primary` | `[:search]` | `SERPER_API_KEY` |
| `brave-primary` | `[:search]` | `BRAVE_API_KEY` |
| `pubmed-primary` | `[:search]` | - |
| `duckduckgo-primary` | `[:search]` | - |

---

## Worker Capabilities System

`Pool.set_capabilities(worker_name, caps)` / `Pool.get_capabilities(worker_name)`

| Capability | Descripción | Workers |
|-----------|-------------|---------|
| `:chat` | Chat completion básico | Todos LLM |
| `:tools` | Function calling | anthropic, gemini, groq, openai, qwen |
| `:vision` | Análisis de imágenes | gemini, openai, qwen |
| `:reasoning` | Razonamiento complejo | anthropic |
| `:long_context` | Contexto >100K tokens | gemini (1M), claude (200K) |
| `:fast` | Baja latencia | groq, qwen |

`/api/tools` sin `provider` → auto-routing entre workers con `:tools` capability.
`/api/tools` con provider sin `:tools` → 400 "does not support tool calling".

---

## Endpoints Principales

| Endpoint | Método | Auth | Descripción |
|----------|--------|------|-------------|
| `POST /api/chat` | POST | ✅ | SSE streaming, `provider:` opcional, failover automático |
| `POST /api/completions` | POST | ✅ | OpenAI-compatible (mismo handler que /chat) |
| `POST /api/tools` | POST | ✅ | Function calling, `provider` opcional, capability validation |
| `POST /api/search` | POST | ✅ | Búsqueda web con múltiples providers |
| `GET /api/models` | GET | ✅ | Lista workers + capabilities + contexto |
| `GET /api/health` | GET | ❌ | Health check básico |
| `GET /api/health/workers` | GET | ❌ | Status detallado de workers |
| `GET /api/health/detailed` | GET | ❌ | Sistema completo + recommendations por task type |
| `GET /api/stats` | GET | ✅ | Estadísticas de uso (requests, tokens, success rate) |
| `GET /api/stats/providers` | GET | ✅ | Estadísticas por provider |
| `GET /` | GET | ❌ | Dashboard HTML con stats en tiempo real |
| `GET /docs` | GET | ❌ | Portal de documentación |
| `GET /docs/api` | GET | ❌ | Referencia API con ejemplos |
| `GET /docs/quickstart` | GET | ❌ | Guía de inicio rápido |

---

## OAuth Workers — IMPLEMENTADOS

### Claude OAuth (✅ Completo)

**Módulos:**
```
lib/cortex_community/auth/claude_cli_reader.ex   ← lee ~/.claude/.credentials.json o Keychain
lib/cortex_community/clients/claude_oauth_client.ex ← llama api.anthropic.com
lib/cortex_community/workers/anthropic_oauth_worker.ex ← worker registrado
```

**Credentials:** `~/.claude/.credentials.json` → campo `claudeAiOauth.accessToken`

**API:**
- Base: `https://api.anthropic.com`
- Endpoint: `/v1/messages?beta=true`
- Headers: `anthropic-beta: oauth-2025-04-20`, `anthropic-dangerous-direct-browser-access: true`

**Worker:** `anthropic-oauth-local`
- Capabilities: `[:chat, :tools, :reasoning]`
- Priority: 5
- Modelo: `claude-sonnet-4-5-20250929`
- Timeout: 60_000ms

**Comandos de test en iex -S mix:**
```elixir
CortexCommunity.Auth.ClaudeCliReader.read_credentials()
CortexCommunity.Auth.ClaudeCliReader.valid?(creds)

{:ok, creds} = CortexCommunity.Auth.ClaudeCliReader.read_credentials()
{:ok, stream} = CortexCommunity.Clients.ClaudeOAuthClient.chat([%{"role" => "user", "content" => "hola"}], creds)
stream |> Enum.join("") |> IO.puts()
```

### Qwen OAuth (✅ Completo)

**Módulos:**
```
lib/cortex_community/auth/qwen_credential_reader.ex ← lee ~/.qwen/oauth_creds.json
lib/cortex_community/workers/qwen_oauth_worker.ex ← worker registrado
```

**Credentials:** `~/.qwen/oauth_creds.json`
```json
{
  "access_token": "...",
  "refresh_token": "...",
  "resource_url": "portal.qwen.ai",
  "expiry_date": 1773102794866
}
```

**API:**
- Base: `https://portal.qwen.ai`
- Endpoint: `/v1/chat/completions` (OpenAI-compatible)
- Auth: `Authorization: Bearer <access_token>`

**Worker:** `qwen-oauth-local`
- Capabilities: `[:chat, :tools, :vision, :fast]`
- Priority: 8 (más alta - free tier)
- Modelo: `coder-model` (Qwen 3.5 Plus)
- Timeout: 30_000ms

**Expiración:** `expiry_date` en ms (comparar con `System.system_time(:millisecond)`)

---

## Model Discovery

**Módulos:**
```
lib/cortex_community/model_discovery/
├── model_selector.ex      ← GenServer principal
├── model_info.ex          ← Context window lookup
├── provider_model.ex      ← Schema DB
└── model_ranking.ex       ← Rankings por task type
```

**Ciclo de vida:**
1. **Startup (3s delay):** Discovery de modelos por provider
2. **Ranking:** Usa `CortexCore.chat/2` para rankear workers por task type
3. **Persistencia:** Guarda en DB (`provider_models`, `model_rankings`)
4. **Health tick (60s):** Check de salud, rotación si unhealthy
5. **Re-discovery (24h):** Re-descubre y re-rankea

**Task types rankeados:**
| Task Type | Descripción | Workers Típicos |
|-----------|-------------|-----------------|
| `chat` | Conversación general | gemini, claude |
| `coding` | Generación de código | qwen, claude, groq |
| `reasoning` | Análisis complejo, math, science | claude-opus, gemini-pro |
| `tools` | Function calling | claude, gemini, groq |
| `long_context` | Documentos >100K tokens | gemini-1.5-pro (2M), claude (200K) |
| `fast` | Tareas simples, velocidad | groq, qwen |

**Métodos públicos:**
```elixir
ModelSelector.get_model("worker-name")      # Modelo activo
ModelSelector.best_worker_for(:coding)      # Mejor worker por task
ModelSelector.get_rankings()                # Todos los rankings
```

**Providers descubiertos:**
- `gemini` (GEMINI_API_KEYS)
- `groq` (GROQ_API_KEYS)
- `openai` (OPENAI_API_KEYS)
- `anthropic` (ANTHROPIC_API_KEYS)
- `cohere` (COHERE_API_KEYS)
- `xai` (XAI_API_KEYS)

---

## Sistema de Autenticación

### API Keys

**Formato:** `ctx_` + base62 encoded bytes (ej: `ctx_AVnjkXxaIgx1MVQaTQ1dGlovAzdqZNAM`)

**Schema:** `cortex_api_keys`
```elixir
schema "cortex_api_keys" do
  field(:key, :string)
  field(:name, :string)
  field(:expires_at, :utc_datetime)
  field(:last_used_at, :utc_datetime)
  field(:is_active, :boolean, default: true)
  belongs_to(:user, CortexUser)
end
```

**Auth header:** `Authorization: Bearer ctx_...`

### User Credentials (OAuth)

**Schema:** `user_credentials`
```elixir
schema "user_credentials" do
  field(:provider, :string)  # "anthropic_cli", "openai", etc.
  field(:auth_type, :string)  # "oauth", "api_key", "token"
  field(:encrypted_data, :binary)
  field(:expires_at, :utc_datetime)
  field(:is_active, :boolean, default: true)
  belongs_to(:user, CortexUser)
end
```

**Encriptación:** AES-256-GCM con key derivada de `SECRET_KEY_BASE`

### Flujo de Autenticación en ChatController

1. Usuario sin auth → usa server API keys (original behavior)
2. Usuario con auth → intenta credenciales del usuario primero
3. Si OAuth falla → fallback a server pool (Gemini/Groq)

---

## Stats Collector

**GenServer:** `CortexCommunity.StatsCollector`

**Métricas trackeadas:**
- Requests totales, completadas, fallidas, no workers
- Requests activas
- Duración total, tokens totales
- Stats por provider
- Hourly stats (últimas 24h)

**Auto-reset:** Cada 24 horas

**Métodos:**
```elixir
StatsCollector.track_request(event_data)
StatsCollector.track_provider(provider, event_data)
StatsCollector.get_stats()
StatsCollector.get_provider_stats()
StatsCollector.get_hourly_stats()
```

---

## Mix Tasks

### `mix cortex.setup`

Wizard interactivo de setup:
- Setup mode: QuickStart o Manual
- Selección de provider (Anthropic CLI, Anthropic API, OpenAI, Google, Groq)
- Lectura de credenciales Claude Code CLI
- Input de API keys
- Guardado encriptado en DB
- Generación de API key para el usuario

**Uso:**
```bash
mix cortex.setup
mix cortex.setup --provider=anthropic
```

### `mix cortex.keygen <nombre-proyecto>`

Genera API key persistente para proyecto cliente:

**Uso:**
```bash
mix cortex.keygen allisbox-production
```

**Output:**
- Genera key sin expiración
- La guarda en DB
- Muestra comando para agregar al `.env`

---

## Testing

```bash
mix test                          # cortex_community (110 tests)
cd ../cortex-core/cortex_core && mix test  # cortex_core (214 tests)
mix format                        # SIEMPRE antes de commit
mix quality                       # format + credo + sobelow
```

---

## Comandos Útiles

```bash
# Servidor
mix server                        # arrancar en :4000

# Database
mix ecto.migrate                  # migraciones
mix ecto.create                   # crear DB
mix ecto.reset                    # drop + create + migrate

# Setup
mix cortex.setup                  # wizard interactivo
mix cortex.keygen <name>          # nueva API key

# Calidad
mix format                        # formatter
mix credo --strict                # linter
mix sobelow --skip                # security audit
mix quality                       # todos arriba

# Tests
mix test                          # todos tests
mix test --failed                 # últimos fallidos
mix test.coverage                 # con cobertura

# Iex OAuth tests
iex -S mix

# Claude OAuth:
CortexCommunity.Auth.ClaudeCliReader.read_credentials()
CortexCommunity.Auth.ClaudeCliReader.valid?(creds)

# Qwen OAuth:
CortexCommunity.Auth.QwenCredentialReader.read_credentials()
CortexCommunity.Auth.QwenCredentialReader.valid?(creds)

# Chat OAuth:
{:ok, creds} = CortexCommunity.Auth.ClaudeCliReader.read_credentials()
{:ok, stream} = CortexCommunity.Clients.ClaudeOAuthClient.chat([%{"role" => "user", "content" => "hola"}], creds)
stream |> Enum.join("") |> IO.puts()

# Model discovery:
CortexCommunity.ModelSelector.get_rankings()
CortexCommunity.ModelSelector.best_worker_for(:coding)

# Stats:
CortexCommunity.StatsCollector.get_stats()
CortexCommunity.StatsCollector.get_provider_stats()

# Pool capabilities:
CortexCore.Workers.Pool.get_capabilities("groq-primary")
CortexCore.Workers.Pool.get_capabilities("anthropic-oauth-local")
```

---

## Estructura de Directorios

```
cortex_community/
├── lib/
│   ├── cortex_community/
│   │   ├── auth/
│   │   │   ├── claude_cli_reader.ex
│   │   │   └── qwen_credential_reader.ex
│   │   ├── clients/
│   │   │   ├── claude_oauth_client.ex
│   │   │   └── claude_web_client.ex (partial)
│   │   ├── workers/
│   │   │   ├── anthropic_oauth_worker.ex
│   │   │   └── qwen_oauth_worker.ex
│   │   ├── model_discovery/
│   │   │   ├── model_selector.ex
│   │   │   ├── model_info.ex
│   │   │   ├── provider_model.ex
│   │   │   └── model_ranking.ex
│   │   ├── cli/
│   │   │   └── prompter.ex
│   │   ├── stats_collector.ex
│   │   ├── cortex_user.ex
│   │   ├── cortex_api_key.ex
│   │   ├── user_credential.ex
│   │   ├── credentials.ex
│   │   ├── users.ex
│   │   └── users_behaviour.ex
│   ├── cortex_community_web/
│   │   ├── controllers/
│   │   │   ├── chat_controller.ex
│   │   │   ├── tools_controller.ex
│   │   │   ├── search_controller.ex
│   │   │   ├── models_controller.ex
│   │   │   ├── health_controller.ex
│   │   │   ├── stats_controller.ex
│   │   │   ├── docs_controller.ex
│   │   │   └── page_controller.ex
│   │   ├── components/
│   │   │   ├── core_components.ex
│   │   │   └── layouts.ex
│   │   ├── plugs/
│   │   │   ├── authenticate_api_key.ex
│   │   │   └── request_logger.ex
│   │   ├── endpoint.ex
│   │   ├── router.ex
│   │   ├── telemetry.ex
│   │   └── gettext.ex
│   ├── mix/
│   │   └── tasks/
│   │       ├── cortex.setup.ex
│   │       └── cortex.keygen.ex
│   ├── cortex_community.ex
│   └── cortex_community_web.ex
├── priv/
│   ├── repo/
│   │   └── migrations/ (7 migraciones)
│   └── static/
├── test/
├── .env.example
├── mix.exs
└── README.md
```

---

## Estado del Proyecto

### ✅ Completamente Implementado

| Categoría | Estado |
|-----------|--------|
| Controladores API | 100% (8 controllers) |
| OAuth Workers | 100% (Anthropic + Qwen) |
| Lectores de Credenciales | 100% (Claude + Qwen) |
| Model Discovery | 100% (Selector + Ranking) |
| Sistema de Usuarios | 100% (Users + API Keys + Credentials) |
| Stats Collector | 100% |
| Mix Tasks | 100% (setup + keygen) |
| UI Components | 100% |
| Database | 100% (6 schemas, 7 migraciones) |

### ⚠️ Parcial / Pendiente

| Módulo | Estado | Pendiente |
|--------|--------|-----------|
| `ClaudeWebClient` | 50% | Método `chat/3` retorna `{:error, :not_yet_implemented}` |
| `DashboardLive` | 0% | Ruta definida en router pero no implementada |
| Token Refresh OAuth | 0% | `refresh_token/1` retorna `{:error, :not_implemented}` |

---

## Environment Variables

```bash
# API Keys (comma-separated para múltiples)
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
WORKER_POOL_STRATEGY=local_first
HEALTH_CHECK_INTERVAL=30000
```

---

## Default API Key

```
ctx_AVnjkXxaIgx1MVQaTQ1dGlovAzdqZNAM
```

Generada en startup, guardada en `/tmp/cortex_api_key.txt` (chmod 600).
