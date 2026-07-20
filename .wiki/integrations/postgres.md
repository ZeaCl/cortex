# PostgreSQL

Base de datos principal de Cortex (Ecto).

## Schemas

| Tabla | Schema | Uso |
|-------|--------|-----|
| `cortex_users` | `CortexUser` | Usuarios locales del gateway |
| `cortex_api_keys` | `CortexApiKey` | API keys `ctx_` (deprecated) |
| `user_credentials` | `UserCredential` | Credenciales OAuth/API de providers |
| `provider_models` | `ProviderModel` | Modelos descubiertos automáticamente |

## Conexión local

```bash
# Docker (ZEA Platform)
docker exec zea_postgres_local psql -U postgres -d cortex_community_dev

# Directa (si tenés Postgres local)
psql -U postgres -d cortex_community_dev
```

## Migraciones

```bash
mix ecto.migrate
mix ecto.rollback
mix ecto.reset
```

## Nota

`config/test.exs` NO configura el Repo. Tests que tocan DB crashean con `missing :database key`. Si se necesita DB en tests, agregar config explícita o wrapper con `try/rescue` en el código de producción.
