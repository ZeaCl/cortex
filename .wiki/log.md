# Log

## [2025-07-24] feat | mix cortex.setup.thalamus
**Descripción**: Creada la mix task `cortex.setup.thalamus` que registra Cortex como OAuth2 client en Thalamus, guarda `THALAMUS_CLIENT_ID`/`THALAMUS_CLIENT_SECRET` en `.env`, y soporta flags `--url` y `--org`.
**Archivos**: lib/mix/tasks/cortex.setup.thalamus.ex
**Issues**: #14

## [2025-07-24] feat | CLI zea-cortex + doctor
**Descripción**: Creada la CLI `zea-cortex` siguiendo el patrón de Cerebelum/Thalamus. Incluye `health`, `doctor` (diagnostica connectivity, Thalamus auth, LLM providers, API keys) y `config set-env local|prod`. Soporta `--zea-discover` y `--zea-manifest`.
**Archivos**: cli/ (9 archivos nuevos)
**Issues**: #13, #16

## [2025-07-24] feat | DeepSeek provider + Thalamus secrets
**Descripción**: Agregado DeepSeekWorker en cortex_core, ThalamusClient.resolve_secret/3, e integración en chat controller para resolver API keys desde Thalamus secrets cuando el usuario está autenticado vía JWT. Esto permite que `zea thalamus secret create --provider deepseek --value sk-...` funcione sin cambios en cortex.
**Archivos**: core/lib/cortex_core/workers/adapters/deepseek_worker.ex, core/lib/cortex_core/workers/supervisor.ex, lib/cortex_community/user_credential.ex, lib/cortex_community/application.ex, lib/cortex_community/auth/thalamus_client.ex, lib/cortex_community_web/controllers/chat_controller.ex
**Issues**: #15, #17

## [2026-07-20] fix | Reparados 5 tests preexistentes
**Diagnóstico**: 3 fallas distintas — ModelsController esperaba 401 pero `/api/models` es público (sin auth plug), HealthController crasheaba con `Repo.all` sin DB configurada, ChatController SSE regex buscaba `"done": true` con espacio pero el JSON real es `"done":true` compacto. **Fix**: stubs + assert 200 para models, `try/rescue` para DB en health controller, regex corregido. 105 tests, 0 failures.

## [2026-07-20] review | Code review — 6 issues encontrados y corregidos
**Hallazgos**: `Jason.decode!` podía crashear con body no-JSON, race condition en creación de tabla ETS, token JWT sin hashear como key de ETS, `@users` dead code en el plug, deprecation warning sin throttling, `stub_local_auth` con parámetro no usado. **Fix**: `Jason.decode` con case, `:ets.new` directo con rescue, SHA256 para cache key, throttling 1/min con ETS, limpio dead code y parámetro.

## [2026-07-20] docs | Documentación estructurada siguiendo patrón Thalamus/Cerebelum
`docs/` reorganizado con index.md (navegación por rol), api/ (6 endpoints), guides/ (thalamus-integration), architecture/overview.md, getting-started.md, configuration.md, deployment.md. Mismo patrón que thalamus y cerebelum: un archivo por endpoint, guías de integración, overview técnico con diagramas.

## [2026-07-20] feat | Fase 6: Deprecación y docs (#6)
`@deprecated` en `CortexApiKey` y `mix cortex.keygen`. Warning throttled (1/min) cuando se usa `ctx_` key en modo `hybrid`. `docs/AUTHENTICATION.md` actualizado con sección Thalamus. `docs/NUTRISNAPS_MIGRATION.md` creado — guía de 1 línea de código para migrar.

## [2026-07-20] feat | Fase 3: AuthManager + refactor plug (#9)
`AuthManager` con 3 modos: `local` (ctx_ keys → Users), `thalamus` (JWT → ThalamusClient), `hybrid` (ambos, default). Plug `AuthenticateApiKey` refactorizado: delega a `AuthManager.authenticate/2`, asigna `cortex_user`, `auth_source`, `auth_claims` al conn. `ChatController` adaptado: ya soportaba `cortex_user = nil`, solo se agregó log de `auth_source` y `client_id`.

## [2026-07-20] feat | Fase 4: Configuración y env vars (#8)
`config/runtime.exs`: bloque `config :cortex_community, :auth` con `mode`, `thalamus_introspect_url`, `thalamus_client_id`, `thalamus_client_secret`, `thalamus_cache_ttl`. `application.ex`: `validate_auth_config!` que levanta si `AUTH_MODE=thalamus` sin credenciales. `test.exs`: `System.put_env("AUTH_MODE", "local")` + `config :cortex_community, :auth, mode: :local` — orden importante: runtime.exs corre después y pisa compile-time config. `.env.example`: sección Auth con defaults de desarrollo.

## [2026-07-20] feat | Fase 2: ThalamusClient (#7)
`ThalamusClient.introspect/1`: POST a `/oauth/introspect` con HTTP Basic auth, cache ETS 60s (configurable), timeout 5s. Usa Req (transitivo de cortex_core). Sin dependencias nuevas. Tests con Plug.Cowboy mock server (Bypass no disponible transitivamente). 9 tests: token activo, inactivo, timeout, cache hit, credenciales inválidas, input inválido.

## [2026-07-20] test | Verificación E2E contra Thalamus local (Docker)
Probado con `internal_login:internal_secret_do_not_expose` en `auth.zea.localhost`. Obtener JWT vía client_credentials → introspect → cache hit → AuthManager hybrid mode. Todo funciona end-to-end.

## [2026-07-20] discover | Thalamus introspect no requiere client auth
La doc de Thalamus dice: "Client authentication for the introspection endpoint is not enforced in the current version." Nuestro cliente manda Basic Auth igual → forward-compatible.

## [2026-07-20] discover | Cerebelum valida JWT localmente con JWKS
Cerebelum no llama a `/oauth/introspect` — descarga JWKS de `/.well-known/jwks.json` y verifica firmas localmente. Más rápido (sin network call) pero sin revocación inmediata. Cortex usa online validation (introspect + cache) — correcto para AI gateway donde la latencia del LLM domina.
