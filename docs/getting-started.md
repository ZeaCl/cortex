# Getting Started

Make your first API call to Cortex in under 2 minutes.

---

## Quickstart

### 1. Start Cortex

```bash
git clone https://github.com/ZeaCl/cortex
cd cortex
mix deps.get
mix ecto.setup
mix phx.server
```

Cortex starts at `http://localhost:4000`.

### 2. Get an API key (dev mode)

```bash
mix cortex.keygen my-first-app
```

> ⚠️ `ctx_` keys are deprecated. In production, use [Thalamus OAuth2 tokens](guides/thalamus-integration.md).

### 3. Make your first request

```bash
curl -X POST http://localhost:4000/api/chat \
  -H "Authorization: Bearer ctx_YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Hello!"}],
    "model": "gemini-2.0-flash"
  }'
```

Response (Server-Sent Events):

```
data: {"content":"Hello"}
data: {"content":"! How"}
data: {"content":" can I"}
data: {"content":" help?"}
event: done
data: {"done":true,"model":"gemini-2.0-flash","worker":"gemini-primary"}
```

---

## Authentication

Cortex supports two authentication methods:

| Method | Header | Use case |
|--------|--------|----------|
| `ctx_` API key | `Authorization: Bearer ctx_...` | Legacy, dev |
| Thalamus JWT | `Authorization: Bearer eyJ...` | Production |

See [Authentication](AUTHENTICATION.md) and [Thalamus Integration](guides/thalamus-integration.md) for details.

---

## Next Steps

- [List available models](api/models.md)
- [Configure providers](configuration.md)
- [Deploy to production](deployment.md)
- [Understand the architecture](architecture/overview.md)
