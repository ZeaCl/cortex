# GET /api/health · /api/health/detailed · /api/stats

Health check, detailed system status, and request statistics.

**Public endpoints** — no authentication required.

---

## GET /api/health

Basic health check.

```bash
curl http://localhost:4000/api/health
```

```json
{
  "status": "healthy",
  "available_workers": 3,
  "total_workers": 5,
  "timestamp": "2026-07-20T12:00:00Z"
}
```

| Field | Values |
|---|---|
| `status` | `healthy` (≥1 worker) or `degraded` (0 workers) |

---

## GET /api/health/detailed

Full system status including worker details, recommendations, and gateway info.

```bash
curl http://localhost:4000/api/health/detailed
```

```json
{
  "status": "healthy",
  "gateway": {
    "version": "1.0.0",
    "core_version": "1.1.0",
    "uptime": "2h 30m",
    "memory_mb": 128
  },
  "llm": {
    "available": 2,
    "total": 3,
    "workers": [
      {
        "name": "gemini-primary",
        "status": "available",
        "model": "gemini-2.0-flash",
        "context_window": 1048576,
        "capabilities": ["chat", "tools", "long_context", "vision"]
      }
    ]
  },
  "search": {
    "available": 1,
    "total": 1,
    "workers": [...]
  },
  "recommendations": {
    "chat": {"primary": "gemini-primary", "fallback": "groq-primary"},
    "search": {"primary": "tavily-primary"}
  },
  "timestamp": "2026-07-20T12:00:00Z"
}
```

---

## GET /api/stats

Request statistics and performance metrics.

```bash
curl http://localhost:4000/api/stats
```

```json
{
  "requests": {
    "total": 1543,
    "completed": 1520,
    "failed": 15,
    "active": 8
  },
  "performance": {
    "average_duration_ms": 2340,
    "total_tokens": 450000
  },
  "uptime": {
    "seconds": 9034,
    "formatted": "2h 30m 34s"
  },
  "timestamp": "2026-07-20T12:00:00Z"
}
```
