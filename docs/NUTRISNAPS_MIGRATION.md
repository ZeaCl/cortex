# NutriSnaps → Cortex: Migración de autenticación

> **TL;DR:** En vez de usar una API key fija `ctx_...`, forwardean el JWT que ya reciben del
> usuario. Es 1 línea de código y no necesitan credenciales nuevas.

---

## Cómo funciona hoy

```elixir
# lib/ai_gateway/llm/cortex.ex (actual)
def analyze(messages, opts) do
  api_key = Application.get_env(:ai_gateway, :cortex_api_key, "")
  # → "ctx_KF2Nhb1wZWot4X2EE1R9zduiW8KEf9Y8"

  Req.post(cortex_url,
    headers: %{"Authorization" => "Bearer #{api_key}"},
    json: %{model: model, messages: messages, ...}
  )
end
```

```bash
# .env
CORTEX_API_KEY=ctx_KF2Nhb1wZWot4X2EE1R9zduiW8KEf9Y8
CORTEX_URL=http://cortex:4000/v1/chat/completions
```

## Cómo funciona con Thalamus

El mobile app ya manda un JWT de Thalamus en cada request:

```
POST /api/analyze/food
Authorization: Bearer eyJhbGciOiJSUzI1NiIs...
```

Ese JWT contiene los `domain_roles` del usuario. NutriSnaps lo forwardea tal cual a Cortex:

```
NutriSnaps API                          Cortex
     │                                     │
     │  Authorization: Bearer <JWT>        │
     ├────────────────────────────────────►│
     │                                     │ ThalamusClient.introspect(JWT)
     │                                     │ → active: true
     │                                     │ → domain_roles: [...]
     │                                     │ → scopes: ["cortex:chat"]
     │                                     │
     │  SSE stream con respuesta           │
     │◄────────────────────────────────────┤
```

### Cambio en código

```diff
  def analyze(messages, opts) do
    model = Keyword.get(opts, :model, "mlx-text")
    url = cortex_url()
-   api_key = Application.get_env(:ai_gateway, :cortex_api_key, "")
+   user_jwt = opts[:user_jwt] || ""

    Req.post(url,
      json: %{model: model, messages: messages, max_tokens: 1024, temperature: 0.1},
      headers: %{
-       "Authorization" => "Bearer #{api_key}",
+       "Authorization" => "Bearer #{user_jwt}",
        "Content-Type" => "application/json"
      },
      receive_timeout: 120_000
    )
    |> handle_response()
  end
```

### Cambio en quien llama

```elixir
# Donde se invoca Cortex.analyze (ej: analyze_handler.ex)
user_jwt = get_req_header(conn, "authorization") |> List.first("")

AiGateway.LLM.Cortex.analyze(messages, user_jwt: user_jwt)
```

### Cambio en .env

```diff
- CORTEX_API_KEY=ctx_KF2Nhb1wZWot4X2EE1R9zduiW8KEf9Y8
+ # Ya no necesitan CORTEX_API_KEY
  CORTEX_URL=http://cortex:4000/v1/chat/completions
```

---

## Ventajas de forwardear el JWT

| Antes (ctx_ key) | Ahora (JWT forward) |
|---|---|
| Una key estática para todo | Cada usuario tiene su identidad |
| No se sabe quién hizo el request | Cortex ve `user_id`, `domain_roles`, `org_id` |
| Si se filtra la key, acceso total | Los JWT expiran en 1 hora |
| Sin auditoría por usuario | Audit logs con identidad real |

---

## Preguntas frecuentes

### ¿Necesito registrar NutriSnaps como cliente OAuth2 en Thalamus?

**No para forwardear.** El JWT ya fue emitido por Thalamus al usuario. NutriSnaps solo lo pasa
de largo. Cortex valida el JWT directamente contra Thalamus.

Si en el futuro NutriSnaps necesita hacer llamadas M2M sin un usuario (ej: un cron que
analiza datos), ahí sí necesitaría su propio client_id/client_secret con grant
`client_credentials`. Pero para el flujo actual no.

### ¿Qué pasa si el JWT expiró?

Thalamus emite JWTs con `expires_in: 3600` (1 hora). Si expiró, Cortex devuelve 401 y
el mobile app renueva su token con refresh_token. NutriSnaps no tiene que hacer nada.

### ¿Y en desarrollo local?

El ambiente local de ZEA ya tiene Thalamus corriendo en `auth.zea.localhost`. Podés
obtener un JWT para probar:

```bash
JWT=$(curl -s -X POST http://auth.zea.localhost/oauth/token \
  -u "internal_login:internal_secret_do_not_expose" \
  -d "grant_type=client_credentials" \
  -d "client_id=internal_login" \
  -d "client_secret=internal_secret_do_not_expose" \
  -d "scope=cortex:chat" | jq -r '.access_token')

curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"model":"mlx-text","messages":[{"role":"user","content":"Hola"}]}'
```

---

## Plan de migración

| Fase | Qué | Riesgo |
|---|---|---|
| **1. Ahora** | Agregar `user_jwt` como opción en `Cortex.analyze/2` | Cero — es backward-compatible |
| **2. Ahora** | Pasar el JWT desde el handler | Cero |
| **3. Verificar** | Monitorear que no haya 401 en logs de Cortex | Bajo |
| **4. Después** | Borrar `CORTEX_API_KEY` del .env | Cero |
