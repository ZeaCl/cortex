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

## Credenciales de desarrollo

Ver `.wiki/rules.md` sección Thalamus.

## Repo

`/Users/dev/Documents/zea/thalamus`
