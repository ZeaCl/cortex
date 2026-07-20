# Thalamus OAuth2 Integration

## Qué se construyó

Cortex como **Resource Server OAuth2** — acepta y valida JWT tokens emitidos por Thalamus, además de las API keys locales `ctx_`.

## Archivos

| Archivo | Rol |
|---------|-----|
| `lib/cortex_community/auth/thalamus_client.ex` | HTTP client para `/oauth/introspect` + cache ETS |
| `lib/cortex_community/auth/auth_manager.ex` | Dispatcher: local / thalamus / hybrid |
| `lib/cortex_community_web/plugs/authenticate_api_key.ex` | Plug refactorizado, delega a AuthManager |
| `lib/cortex_community_web/controllers/chat_controller.ex` | Adaptado para `cortex_user = nil` |
| `config/runtime.exs` | Bloque `config :cortex_community, :auth` |
| `config/test.exs` | `System.put_env("AUTH_MODE", "local")` |
| `lib/cortex_community/application.ex` | `validate_auth_config!` |

## Decisiones de diseño

### ¿Por qué online validation (introspect) y no JWKS?
Cerebelum usa JWKS (validación local, sin network call). Cortex usa online validation porque:
1. La latencia del LLM domina (segundos) — 50ms extra de introspect no se notan
2. Cache ETS 60s elimina el 99% de las llamadas repetidas
3. Revocación inmediata — si un token se revoca, se detecta en máximo 60s
4. Más simple — no requiere manejar rotación de claves públicas

Se puede migrar a JWKS en el futuro sin cambios en la API pública (AuthManager abstrae el detalle).

### ¿Por qué 3 modos y no borrar `local` directamente?
- `local` permite desarrollo sin Thalamus corriendo
- `hybrid` permite migración gradual (NutriSnaps forwardea JWT, otros siguen con ctx_)
- `thalamus` es el end state

### ¿Por qué forwardear JWT en vez de M2M?
Cuando NutriSnaps llama a Cortex en nombre de un usuario, forwardear el JWT del usuario permite:
- Auditoría: Cortex sabe QUIÉN hizo el request
- Autorización: `domain_roles` del usuario determinan scopes
- Sin credenciales额外: NutriSnaps no necesita su propio client_id/secret para M2M

## Lo que aprendimos

1. **Thalamus introspect no requiere client auth** (aún) — nuestro cliente lo manda igual, forward-compatible
2. **Cerebelum usa JWKS** — patrón alternativo más eficiente, pero con tradeoffs distintos
3. **`config/runtime.exs` pisa `test.exs`** — los `System.put_env` en test.exs son necesarios
4. **ETS tiene race condition** con el patrón `whereis` + `new` — mejor `new` directo con rescue
5. **Bypass no está disponible transitivamente** — usar `Plug.Cowboy.http` + `Agent` con nombre

## Issues relacionados

- #7 — ThalamusClient
- #8 — Configuración
- #9 — AuthManager + plug refactor
- #6 — Deprecación
- #5 — Epic: Integración OAuth2 con Thalamus
