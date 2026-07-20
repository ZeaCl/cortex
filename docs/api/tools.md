# POST /api/tools

Provider-native tool calling.

---

## Request

```bash
POST /api/tools
Content-Type: application/json
Authorization: Bearer <token>
```

### Body

| Field | Type | Required | Description |
|---|---|---|---|
| `provider` | String | ✅ | Target provider |
| `tools` | Array | ✅ | Tool definitions |
| `messages` | Array | ✅ | Chat messages for context |

### Example

```bash
curl -X POST http://localhost:4000/api/tools \
  -H "Authorization: Bearer ctx_..." \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "anthropic-primary",
    "tools": [
      {
        "name": "get_weather",
        "description": "Get the current weather",
        "parameters": {
          "type": "object",
          "properties": {
            "location": {"type": "string"}
          }
        }
      }
    ],
    "messages": [
      {"role": "user", "content": "What is the weather in Paris?"}
    ]
  }'
```

---

## Response

```json
{
  "tool_calls": [
    {
      "id": "tool_abc123",
      "name": "get_weather",
      "arguments": {"location": "Paris, France"}
    }
  ]
}
```

---

## Error Responses

| Status | Meaning |
|---|---|
| `400` | Missing required fields |
| `401` | Invalid or missing auth token |
| `500` | Provider error |
