# POST /api/search

Web search via Tavily, Serper, Brave, PubMed, or DuckDuckGo.

---

## Request

```bash
POST /api/search
Content-Type: application/json
Authorization: Bearer <token>
```

### Body

| Field | Type | Required | Description |
|---|---|---|---|
| `query` | String | ✅ | Search query |
| `max_results` | Number | ❌ | Max results (default: 10) |
| `provider` | String | ❌ | Target search engine |

### Example

```bash
curl -X POST http://localhost:4000/api/search \
  -H "Authorization: Bearer ctx_..." \
  -H "Content-Type: application/json" \
  -d '{
    "query": "Elixir Phoenix framework latest version",
    "max_results": 5
  }'
```

---

## Response

```json
{
  "results": [
    {
      "title": "Phoenix Framework",
      "url": "https://www.phoenixframework.org/",
      "snippet": "Phoenix is a web framework for Elixir..."
    }
  ],
  "provider": "tavily-primary",
  "total": 5
}
```

---

## Error Responses

| Status | Meaning |
|---|---|
| `400` | Missing `query` or invalid `provider` |
| `401` | Invalid or missing auth token |
| `404` | Specified provider not found |
| `500` | Unexpected search error |
| `502` | Provider returned HTTP error |
| `503` | No search workers available |
