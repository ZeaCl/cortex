# Cortex Documentation

Cortex is ZEA's AI gateway — a unified API for LLM chat, model discovery, search, and tool execution. Use it **on-premise** (your own infrastructure) or as part of the **ZEA Platform** with Thalamus OAuth2 authentication.

---

## What are you trying to do?

| I want to... | Start here |
|---|---|
| 🟦 **Call an AI model** (chat, search, tools) | [Getting Started →](getting-started.md) |
| 🔐 **Set up authentication** (API keys or Thalamus JWT) | [Authentication →](AUTHENTICATION.md) |
| 🤖 **Integrate as an AI agent / M2M service** | [Thalamus Integration →](guides/thalamus-integration.md) |
| 🟢 **Deploy Cortex on my own infra** | [Deployment →](deployment.md) |
| 🟣 **Configure workers, models, API keys** | [Configuration →](configuration.md) |
| 🟡 **Understand the architecture** | [Architecture Overview →](architecture/overview.md) |

---

## API Reference

| Endpoint | Description |
|---|---|
| [`POST /api/chat`](api/chat.md) | Streaming chat with LLM models |
| [`GET /api/models`](api/models.md) | List available models and context windows |
| [`POST /api/search`](api/search.md) | Web search via Tavily, Serper, Brave |
| [`POST /api/tools`](api/tools.md) | Provider-native tool calling |
| [`GET /api/health`](api/health.md) | Health check and detailed status |
| [`GET /api/stats`](api/health.md#stats) | Request statistics |

---

## Guides

| Guide | Description |
|---|---|
| [Thalamus Integration](guides/thalamus-integration.md) | OAuth2 JWT auth, M2M tokens, auth modes, migration from ctx_ keys |
| [NutriSnaps Migration](NUTRISNAPS_MIGRATION.md) | Migrating NutriSnaps from ctx_ keys to Thalamus JWT |

---

## Operations

| Guide | Description |
|---|---|
| [Deployment](deployment.md) | Docker, fly.io, on-prem, ZEA Platform |
| [Configuration](configuration.md) | Environment variables, workers, models, auth modes |

---

## Architecture

| Guide | Description |
|---|---|
| [Architecture Overview](architecture/overview.md) | Majestic Monolith, plug pipeline, auth flow, worker pool |

---

## Links

- [GitHub](https://github.com/ZeaCl/cortex)
- [Thalamus Docs](https://github.com/ZeaCl/thalamus/docs/index.md)
- [Cerebelum Docs](https://github.com/ZeaCl/cerebelum/docs/index.md)
