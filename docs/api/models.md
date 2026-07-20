# GET /api/models

List available AI models, their context windows, capabilities, and how to use them.

**Public endpoint** — no authentication required.

---

## Request

```bash
GET /api/models
```

---

## Response

```json
{
  "llm": [
    {
      "id": "gemini-primary",
      "service": "llm",
      "provider_type": "gemini",
      "model": "gemini-2.0-flash",
      "status": "available",
      "context_window": 1048576,
      "capabilities": ["chat", "tools", "long_context", "vision"],
      "how_to_use": {
        "endpoint": "POST /api/chat",
        "note": "Use 'provider' to target this model. Without 'provider', uses best available.",
        "example": {
          "provider": "gemini-primary",
          "messages": [{"role": "user", "content": "your message"}]
        }
      }
    }
  ],
  "search": [
    {
      "id": "tavily-primary",
      "service": "search",
      "provider_type": "search",
      "model": null,
      "status": "available",
      "context_window": null,
      "capabilities": ["search"],
      "how_to_use": {
        "endpoint": "POST /api/search",
        "note": "Use 'provider' to target this search engine.",
        "example": {
          "provider": "tavily-primary",
          "query": "your search query",
          "max_results": 10
        }
      }
    }
  ],
  "total": 5,
  "available": 3
}
```

### Worker fields

| Field | Description |
|---|---|
| `id` | Worker name (use as `provider`) |
| `service` | `llm` or `search` |
| `provider_type` | `gemini`, `anthropic`, `openai`, `groq`, `search`, etc. |
| `model` | Default model name |
| `status` | `available`, `unavailable`, `rate_limited` |
| `context_window` | Max tokens in context window |
| `capabilities` | `chat`, `tools`, `vision`, `long_context`, `reasoning`, `search`, `fast` |
| `how_to_use` | Endpoint and example payload |

---

## Example

```bash
curl http://localhost:4000/api/models | jq '.llm[] | {id, model, status}'
```
