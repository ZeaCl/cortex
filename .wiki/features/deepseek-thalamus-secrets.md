# DeepSeek Provider + Thalamus Secrets

## Qué se construyó

1. **DeepSeekWorker** — nuevo worker en cortex_core para modelos DeepSeek (API compatible con OpenAI)
2. **ThalamusClient.resolve_secret/3** — resuelve API keys desde Thalamus secrets (`/api/internal/secrets/resolve`)
3. **Integración en chat controller** — cuando un usuario autenticado vía JWT no tiene credenciales en DB, cortex intenta resolver la API key desde Thalamus secrets

## Archivos

| Archivo | Cambio |
|---------|--------|
| `core/lib/cortex_core/workers/adapters/deepseek_worker.ex` | Nuevo — worker para DeepSeek (deepseek-chat, deepseek-reasoner) |
| `deps/cortex_core/lib/cortex_core/workers/adapters/deepseek_worker.ex` | Copia sincronizada |
| `core/lib/cortex_core/workers/supervisor.ex` | Agregado `maybe_add_deepseek_worker` + `create_worker(:deepseek, ...)` |
| `deps/cortex_core/lib/cortex_core/workers/supervisor.ex` | Copia sincronizada |
| `lib/cortex_community/user_credential.ex` | Agregado `"deepseek"` a providers válidos |
| `lib/cortex_community/application.ex` | Agregado `deepseek-primary` a capacidades |
| `lib/cortex_community/auth/thalamus_client.ex` | Agregado `resolve_secret/3` + helpers |
| `lib/cortex_community_web/controllers/chat_controller.ex` | Agregado `try_thalamus_secret/5`, reconocimiento de modelos deepseek, paso de `auth_claims` |

## Decisiones de diseño

### ¿Por qué DeepSeekWorker separado y no reusar OpenAIWorker?
Aunque la API es compatible, tener un worker dedicado permite:
- Defaults específicos (modelo `deepseek-chat`, timeout 60s)
- Prioridad independiente (4 vs 5 de OpenAI)
- Diferenciación en logs y métricas

### ¿Por qué resolver secrets en el controller y no en el supervisor?
El supervisor configura workers con API keys de servidor (env vars). Los secrets de Thalamus son por usuario/org — se resuelven en el controller cuando el request viene con un JWT autenticado. Esto permite que `zea thalamus secret create --provider deepseek --value sk-...` funcione sin reiniciar cortex.

### Flujo completo
```
1. Usuario hace zea thalamus secret create --provider deepseek --value sk-...
2. Cliente llama a POST /api/chat con JWT (con sub y organization_id)
3. ChatController intenta:
   a) Credentials DB del usuario → fallback
   b) ThalamusClient.resolve_secret("deepseek", user_sub, org_id) → ✅
   c) API keys del servidor (env vars)
```

## Lo que aprendimos

1. DeepSeek usa exactamente el mismo formato de API que OpenAI — el worker es prácticamente un copy con distintos defaults
2. El endpoint de Thalamus para resolver secrets es interno (`/api/internal/secrets/resolve`) — no requiere autenticación extra
3. Los `auth_claims` del JWT no se estaban pasando a `try_user_credentials` — hubo que agregarlos como parámetro

## Issues relacionados

- #17 — Agregar DeepSeek como provider
- #15 — Resolver API keys desde Thalamus secrets
