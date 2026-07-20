# Deployment

How to deploy Cortex in different environments.

---

## Docker

### Single container

```dockerfile
FROM hexpm/elixir:1.19.5-erlang-27.3.4-debian-bookworm-20250519 AS builder
WORKDIR /app
COPY . .
RUN mix deps.get && mix compile
RUN mix release cortex_community

FROM debian:bookworm-slim
COPY --from=builder /app/_build/prod/rel/cortex_community /app
ENV PHX_SERVER=true
EXPOSE 4000
CMD ["/app/bin/cortex_community", "start"]
```

```bash
docker build -t cortex .
docker run -p 4000:4000 \
  -e SECRET_KEY_BASE=$(mix phx.gen.secret) \
  -e GEMINI_API_KEYS=... \
  -e DATABASE_URL=ecto://user:pass@host/cortex_prod \
  cortex
```

### Docker Compose (ZEA Platform)

```yaml
# Part of the ZEA local dev environment
# See /Users/dev/Documents/zea/skills/local-dev/SKILL.md

services:
  cortex:
    build: ../cortex
    ports:
      - "4000:4000"
    environment:
      - AUTH_MODE=hybrid
      - THALAMUS_INTROSPECT_URL=http://thalamus:4000/oauth/introspect
      - THALAMUS_CLIENT_ID=cortex-service
      - THALAMUS_CLIENT_SECRET=...
      - GEMINI_API_KEYS=...
      - DATABASE_URL=ecto://postgres:postgres@postgres:5432/cortex_prod
    depends_on:
      - postgres
      - thalamus
```

---

## fly.io

```bash
fly launch
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)
fly secrets set GEMINI_API_KEYS=...
fly secrets set AUTH_MODE=thalamus
fly secrets set THALAMUS_CLIENT_ID=...
fly secrets set THALAMUS_CLIENT_SECRET=...
fly deploy
```

---

## Production Checklist

- [ ] Set `AUTH_MODE=thalamus` (or `hybrid` during migration)
- [ ] Configure `SECRET_KEY_BASE` (use `mix phx.gen.secret`)
- [ ] Set `PHX_HOST` to your domain
- [ ] Configure at least one LLM provider (Gemini, Anthropic, etc.)
- [ ] Set up PostgreSQL with `DATABASE_URL`
- [ ] Enable health checks: `HEALTH_CHECK_INTERVAL=300`
- [ ] Put Cortex behind a reverse proxy (Caddy, nginx) with HTTPS
- [ ] Register Cortex as an OAuth2 client in Thalamus
