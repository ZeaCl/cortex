# Configuration

All Cortex configuration via environment variables.

---

## Auth

| Variable | Default | Description |
|---|---|---|
| `AUTH_MODE` | `hybrid` | `local`, `thalamus`, or `hybrid` |
| `THALAMUS_INTROSPECT_URL` | `https://auth.zea.cl/oauth/introspect` | Token introspection endpoint |
| `THALAMUS_CLIENT_ID` | — | OAuth2 client ID (required for thalamus/hybrid) |
| `THALAMUS_CLIENT_SECRET` | — | OAuth2 client secret (required for thalamus/hybrid) |
| `THALAMUS_CACHE_TTL` | `60` | Introspect cache TTL in seconds |

### Auth modes

| Mode | ctx_ keys | JWT (Thalamus) | Use case |
|---|---|---|---|
| `local` | ✅ | ❌ | Development |
| `hybrid` | ✅ (with warning) | ✅ | Migration (default) |
| `thalamus` | ❌ | ✅ | Production |

---

## Server

| Variable | Default | Description |
|---|---|---|
| `PORT` | `4000` | HTTP server port |
| `PHX_HOST` | `localhost` | Host for URL generation |
| `SECRET_KEY_BASE` | — | Phoenix secret (required in prod) |
| `PHX_SERVER` | — | Set to `true` to start the server in releases |

---

## LLM Providers

Cortex auto-discovers workers from environment variables. Add any of these:

```bash
# Anthropic
ANTHROPIC_API_KEYS=sk-ant-api03-key1,key2

# OpenAI
OPENAI_API_KEYS=sk-key1,key2

# Google Gemini
GEMINI_API_KEYS=AIzaSyKey1,key2

# Gemini Pro 2.5 (separate quota)
GEMINI_PRO_25_API_KEYS=AIzaSyKey1

# Groq
GROQ_API_KEYS=gsk_key1,key2

# xAI (Grok)
XAI_API_KEYS=xai-key1

# Cohere
COHERE_API_KEYS=key1

# Ollama (local)
OLLAMA_BASE_URL=http://localhost:11434
```

---

## Search Providers

```bash
TAVILY_API_KEY=tvly-key
SERPER_API_KEY=key
BRAVE_API_KEY=key
```

---

## Worker Pool

| Variable | Default | Description |
|---|---|---|
| `WORKER_POOL_STRATEGY` | `local_first` | `local_first`, `round_robin`, `least_used`, `random` |
| `HEALTH_CHECK_INTERVAL` | `0` | Worker health check interval in seconds (0 = disabled) |

---

## Database

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | — | Ecto database URL (ecto://user:pass@host/db) |

---

## Example .env

```bash
# Auth
AUTH_MODE=hybrid
THALAMUS_INTROSPECT_URL=http://auth.zea.localhost/oauth/introspect
THALAMUS_CLIENT_ID=cortex-local
THALAMUS_CLIENT_SECRET=dev-secret

# Server
PORT=4000

# Providers (at least one required)
GEMINI_API_KEYS=AIzaSy...
GROQ_API_KEYS=gsk_...
```
