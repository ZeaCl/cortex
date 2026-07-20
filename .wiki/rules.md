# Reglas y Patrones

## Convenciones de código

### Auth
- `AuthManager` es el único entry point para autenticación — nunca llamar `ThalamusClient` o `Users` directo desde plugs/controllers
- Modo `local` DEBE preservar comportamiento exacto anterior (sin prefijo `ctx_` forzado en local mode, backward compat con tests)
- Nuevos errores de auth requieren entrada en `format_error_message/1` del plug

### Config
- `config/runtime.exs` **pisa** compile-time config de `config/test.exs` — si test.exs necesita forzar un valor, usar `System.put_env` ANTES del `config`
- Toda lectura de config de auth usa `Application.get_env(:cortex_community, :auth)` — nunca `System.get_env` directo en runtime

### Tests
- `Mox.verify_on_exit!` en `ConnCase` — todo mock debe tener `expect` o `stub`
- Mock servers HTTP usan `Plug.Cowboy` + `Agent` con nombre para cross-process state
- Tests de timeout requieren `async: false` (bloquean el scheduler)

### ETS
- Siempre usar `:ets.new` directo con `rescue ArgumentError` — no `:ets.whereis` + `:ets.new` (race condition)

## Problemas conocidos

### test.exs vs runtime.exs
`config/runtime.exs` se evalúa en runtime, después de `config/test.exs` (compile-time). Si ambos definen la misma key, runtime.exs gana. Workaround: `System.put_env` en test.exs para que runtime.exs lea el valor correcto.

### Bypass no disponible en tests
`Bypass` es dep de `cortex_core` con `only: :test` — no disponible transitivamente. Alternativa: `Plug.Cowboy.http` + `Agent` con nombre registrado.

### DB en tests
Sin `config :cortex_community, CortexCommunity.Repo` en test.exs, cualquier `Repo.all/1` crashea. Si un controller usa `Repo`, hay que wrappear con `try/rescue` o configurar DB de test.

## Thalamus

### Conexión local
```bash
# Obtener JWT para desarrollo
curl -s -X POST http://auth.zea.localhost/oauth/token \
  -u "internal_login:internal_secret_do_not_expose" \
  -d "grant_type=client_credentials" \
  -d "client_id=internal_login" \
  -d "client_secret=internal_secret_do_not_expose" \
  -d "scope=cortex:chat" | jq -r '.access_token'

# Introspect
curl -s -X POST http://auth.zea.localhost/oauth/introspect \
  -u "internal_login:internal_secret_do_not_expose" \
  -d "token=$JWT" | jq
```

### Credenciales de desarrollo
| Client | ID | Secret |
|--------|----|--------|
| Internal Login | `internal_login` | `internal_secret_do_not_expose` |
| Cerebelum | `cerebelum_service` | `cerebelum_service_secret_change_in_production` |

### Docker
```bash
docker ps | grep thalamus
docker exec zea_postgres_local psql -U postgres -d thalamus_prod
```
