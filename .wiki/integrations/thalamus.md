# Thalamus

OAuth2 / OpenID Connect identity provider de ZEA. Cortex lo usa para validar JWT tokens vía `/oauth/introspect`.

## Conexión

| Entorno | URL |
|---------|-----|
| Prod | `https://auth.zea.cl` |
| Local (Docker) | `http://auth.zea.localhost` |

## Endpoints usados por Cortex

| Endpoint | Uso |
|----------|-----|
| `POST /oauth/introspect` | Validar JWT (ThalamusClient) |
| `POST /oauth/token` | Obtener JWT (client_credentials, solo para testing) |
| `GET /api/internal/secrets/resolve` | Resolver API keys de AI providers (ThalamusClient.resolve_secret/3) |
| `POST /api/clients` | Registrar cortex como OAuth2 client (mix cortex.setup.thalamus) |

## Registrar cortex como OAuth2 client

```bash
# Automático
mix cortex.setup.thalamus

# Con URL y org explícitas
mix cortex.setup.thalamus --url=http://auth.zea.localhost --org=zea

# Manual (vía CLI)
zea thalamus auth login
zea thalamus client create \
  --name "cortex" \
  --type confidential \
  --grants "client_credentials" \
  --scopes "cortex:chat"
```

## Credenciales de desarrollo

Ver `.wiki/rules.md` sección Thalamus.

## Repo

`/Users/dev/Documents/zea/thalamus`
