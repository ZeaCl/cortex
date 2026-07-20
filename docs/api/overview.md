# API Reference

Base URL: `http://localhost:4000` (dev) | `https://api.zea.cl` (prod)

---

## Authentication

| Method | Header |
|---|---|
| Local API key | `Authorization: Bearer ctx_...` |
| Thalamus JWT | `Authorization: Bearer eyJ...` |

See [Authentication](../AUTHENTICATION.md) for details.

---

## Public Endpoints

These endpoints do not require authentication:

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/health` | Basic health check |
| `GET` | `/api/health/detailed` | Full system status |
| `GET` | `/api/stats` | Request statistics |
| `GET` | `/api/models` | Available models |

---

## Authenticated Endpoints

These require an `Authorization` header:

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/chat` | Streaming chat with LLM |
| `POST` | `/api/search` | Web search |
| `POST` | `/api/tools` | Tool calling |

---

## Response Format

### Success

All endpoints return JSON:

```json
{
  "status": "healthy",
  "available_workers": 3,
  "total_workers": 5,
  "timestamp": "2026-07-20T..."
}
```

### Errors

```json
{
  "error": true,
  "message": "Missing required field: messages",
  "timestamp": "2026-07-20T..."
}
```

### Streaming (Chat)

Chat responses use Server-Sent Events (SSE):

```
data: {"content":"Hello"}
data: {"content":" world"}
event: done
data: {"done":true,"model":"gemini-2.0-flash","worker":"gemini-primary"}
```

---

## Rate Limiting

Rate limiting is handled at the reverse proxy level (Caddy, nginx). Cortex itself does not enforce rate limits per API key.

---

## API Docs

| Endpoint | Guide |
|---|---|
| `POST /api/chat` | [Chat](chat.md) |
| `GET /api/models` | [Models](models.md) |
| `POST /api/search` | [Search](search.md) |
| `POST /api/tools` | [Tools](tools.md) |
| `GET /api/health` | [Health](health.md) |
