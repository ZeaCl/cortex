# Architecture Overview

Cortex follows a **Majestic Monolith** architecture — the web layer, API, and core AI logic live in a single cohesive Elixir application.

---

## Layers

```
┌──────────────────────────────────────────────────────────────────┐
│                     CortexCommunity (Phoenix App)                 │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Web Layer (cortex_community_web)                          │  │
│  │                                                             │  │
│  │  Router ─► Plugs (Auth) ─► Controllers                     │  │
│  │     │                         │                             │  │
│  │     │  GET  /api/health       │  HealthController          │  │
│  │     │  GET  /api/models       │  ModelsController          │  │
│  │     │  POST /api/chat         │  ChatController (SSE)      │  │
│  │     │  POST /api/search       │  SearchController          │  │
│  │     │  POST /api/tools        │  ToolsController           │  │
│  │     │  GET  /api/stats        │  StatsController           │  │
│  └────────────────────────────────────────────────────────────┘  │
│                               │                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Auth Layer (cortex_community/auth)                        │  │
│  │                                                             │  │
│  │  AuthenticateApiKey Plug                                   │  │
│  │       │                                                     │  │
│  │       ▼                                                     │  │
│  │  AuthManager                                               │  │
│  │    ├─ :local    → Users.authenticate_by_api_key()          │  │
│  │    ├─ :thalamus → ThalamusClient.introspect()              │  │
│  │    └─ :hybrid   → both                                     │  │
│  │                                                             │  │
│  │  ThalamusClient                                            │  │
│  │    └─ POST /oauth/introspect + ETS cache (60s TTL)         │  │
│  └────────────────────────────────────────────────────────────┘  │
│                               │                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Core Layer (cortex_core)                                  │  │
│  │                                                             │  │
│  │  Worker Pool (local_first, round_robin, least_used)        │  │
│  │    ├─ AnthropicWorker     (Claude)                          │  │
│  │    ├─ GeminiWorker        (Gemini 2.0 Flash / Pro)         │  │
│  │    ├─ OpenAIWorker        (GPT-5, O3, O4-mini)             │  │
│  │    ├─ GroqWorker          (Llama, Mixtral)                 │  │
│  │    ├─ XAIWorker           (Grok)                           │  │
│  │    ├─ CohereWorker        (Command)                        │  │
│  │    ├─ OllamaWorker        (Local models)                   │  │
│  │    ├─ TavilyWorker        (Web search)                     │  │
│  │    ├─ SerperWorker        (Web search)                     │  │
│  │    ├─ BraveWorker         (Web search)                     │  │
│  │    ├─ PubMedWorker        (Academic search)                │  │
│  │    └─ DuckDuckGoWorker    (Web search)                     │  │
│  │                                                             │  │
│  │  ModelSelector — health-based ranking + failover            │  │
│  │  StatsCollector — request metrics                          │  │
│  └────────────────────────────────────────────────────────────┘  │
│                               │                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Data Layer                                                │  │
│  │                                                             │  │
│  │  PostgreSQL (Ecto)                                         │  │
│  │    ├─ cortex_users                                         │  │
│  │    ├─ cortex_api_keys (ctx_)                               │  │
│  │    ├─ user_credentials (OAuth, API keys)                   │  │
│  │    └─ provider_models (discovery)                          │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## Request Flow (Chat)

```
Client                    Cortex                            Provider
  │                         │                                  │
  │  POST /api/chat         │                                  │
  │  Authorization: Bearer  │                                  │
  │────────────────────────►│                                  │
  │                         │                                  │
  │                    ┌────┴─────┐                            │
  │                    │ Auth Plug │                            │
  │                    └────┬─────┘                            │
  │                         │                                  │
  │              ┌──────────┴──────────┐                       │
  │              │   AuthManager       │                       │
  │              │   (hybrid mode)     │                       │
  │              └──────────┬──────────┘                       │
  │                         │                                  │
  │            ┌────────────┴────────────┐                     │
  │            │ ctx_ → Users.auth       │                     │
  │            │ JWT  → ThalamusClient   │                     │
  │            └────────────┬────────────┘                     │
  │                         │                                  │
  │                    ┌────┴─────┐                            │
  │                    │ ChatCtrl │                            │
  │                    └────┬─────┘                            │
  │                         │                                  │
  │                   ┌─────┴──────┐                           │
  │                   │ ModelSelect│                           │
  │                   └─────┬──────┘                           │
  │                         │                                  │
  │                         │  POST /v1/models/chat            │
  │                         │─────────────────────────────────►│
  │                         │                                  │
  │                         │  SSE stream                      │
  │                         │◄─────────────────────────────────│
  │                         │                                  │
  │  SSE stream             │                                  │
  │◄────────────────────────│                                  │
```

---

## Auth Modes

See [Thalamus Integration](guides/thalamus-integration.md) for details.

| Mode | ctx_ keys | JWT (Thalamus) | Description |
|---|---|---|---|
| `local` | ✅ | ❌ | Dev mode — no Thalamus dependency |
| `hybrid` | ✅ (deprecated) | ✅ | Migration mode |
| `thalamus` | ❌ | ✅ | Production — full OAuth2 |
