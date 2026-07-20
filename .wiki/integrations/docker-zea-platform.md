# Docker — ZEA Platform (Local)

Entorno de desarrollo local que replica producción. Incluye Thalamus, Cerebelum, Cranium, fm_*, PostgreSQL, Redis.

## Servicios relevantes para Cortex

| Servicio | URL | Puerto |
|----------|-----|--------|
| Thalamus | `http://auth.zea.localhost` | 4000 (interno) |
| PostgreSQL | `localhost:5432` | 5432 |

## Comandos

```bash
# Ver estado
docker ps | grep -E "thalamus|postgres"

# Conectarse a PostgreSQL
docker exec zea_postgres_local psql -U postgres -d thalamus_prod

# Reiniciar Thalamus
docker compose -f ~/Documents/zea/zea/docker-compose.local.yml restart thalamus

# Logs
docker logs zea_thalamus_local --tail 50
```

## Ver también

- Skill: `/Users/dev/Documents/zea/skills/local-dev/SKILL.md`
- Repo compose: `/Users/dev/Documents/zea/zea`
