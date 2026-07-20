# POST /api/chat

Streaming chat completion with automatic provider selection and failover.

---

## Request

```bash
POST /api/chat
Content-Type: application/json
Authorization: Bearer <token>
```

### Body

| Field | Type | Required | Description |
|---|---|---|---|
| `messages` | Array | ✅ | Chat messages with `role` and `content` |
| `model` | String | ❌ | Target model (e.g., `claude-sonnet-4-20250514`) |
| `provider` | String | ❌ | Target provider (e.g., `anthropic-primary`) |
| `temperature` | Number | ❌ | 0.0 – 2.0 |
| `max_tokens` | Number | ❌ | Max output tokens |
| `stream` | Boolean | ❌ | Always `true` (SSE) |

### Example

```bash
curl -X POST http://localhost:4000/api/chat \
  -H "Authorization: Bearer ctx_..." \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "What is Elixir?"}
    ],
    "model": "gemini-2.0-flash",
    "temperature": 0.7
  }'
```

---

## Response

Server-Sent Events (SSE) stream:

```
data: {"content":"Elixir"}
data: {"content":" is a"}
data: {"content":" functional"}
data: {"content":" programming"}
data: {"content":" language..."}
event: done
data: {"done":true,"model":"gemini-2.0-flash","worker":"gemini-primary"}
```

### Done event

```json
{
  "done": true,
  "model": "gemini-2.0-flash",
  "worker": "gemini-primary",
  "failover": ["openai-primary"],
  "ratelimit": {
    "remaining": 99,
    "reset": 60
  }
}
```

---

## Provider Selection

Cortex automatically selects the best available provider:

1. If `provider` is specified → use that worker
2. If `model` is specified → route to the provider that serves that model
3. Otherwise → use the highest-ranked healthy provider

Providers are ranked by health status, latency, and capability match.

---

## Error Responses

| Status | Meaning |
|---|---|
| `400` | Invalid request (missing `messages`, not an array) |
| `401` | Invalid or missing auth token |
| `500` | All providers failed |
| `503` | No workers available |

```json
{
  "error": true,
  "message": "No AI workers available at this moment",
  "timestamp": "2026-07-20T..."
}
```
