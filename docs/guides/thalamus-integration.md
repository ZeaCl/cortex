# Thalamus Integration

Cortex integrates with [Thalamus](https://github.com/ZeaCl/thalamus) — ZEA's OAuth2 / OpenID Connect identity provider — for machine-to-machine authentication and JWT-based authorization.

---

## Integration Points

```
┌──────────────┐                    ┌──────────────────┐
│    Cortex    │                    │     Thalamus     │
│              │                    │                  │
│  ┌────────┐  │  ① JWT Validation │  ┌────────────┐  │
│  │Auth    │──┼──────────────────→│  │  /oauth/    │  │
│  │Manager │  │  POST introspect  │  │  introspect │  │
│  └────────┘  │←── active + claims│  └────────────┘  │
│              │                    │                  │
│  ┌────────┐  │  ② M2M Token      │  ┌────────────┐  │
│  │Thalamus│──┼──────────────────→│  │  /oauth/    │  │
│  │Client  │  │  client_credentials│  │  token     │  │
│  └────────┘  │←── access_token   │  └────────────┘  │
│              │                    │                  │
│  ETS Cache   │  ③ Cache (60s)    │                  │
│  ┌────────┐  │  Avoids repeated  │                  │
│  │introsp │  │  introspect calls │                  │
│  └────────┘  │                    │                  │
└──────────────┘                    └──────────────────┘
```

| # | Integration | Purpose |
|---|---|---|
| ① | **JWT Validation** | Validate tokens via `/oauth/introspect` |
| ② | **M2M Token Flow** | Client credentials grant for service-to-service |
| ③ | **ETS Cache** | 60-second TTL cache for introspect results |

---

## Auth Modes

Cortex supports three authentication modes controlled by `AUTH_MODE`:

| Mode | ctx_ keys | JWT (Thalamus) | Use case |
|---|---|---|---|
| `local` | ✅ | ❌ | Development — no Thalamus dependency |
| `hybrid` (default) | ✅ (deprecated) | ✅ | Migration — both methods work |
| `thalamus` | ❌ | ✅ | Production — full OAuth2 |

### Switching modes

```bash
# .env
AUTH_MODE=hybrid
THALAMUS_INTROSPECT_URL=http://auth.zea.localhost/oauth/introspect
THALAMUS_CLIENT_ID=cortex-service
THALAMUS_CLIENT_SECRET=your-secret
```

---

## JWT Flow (Thalamus Mode)

### 1. Client obtains a JWT from Thalamus

```bash
curl -X POST https://auth.zea.cl/oauth/token \
  -u "CLIENT_ID:CLIENT_SECRET" \
  -d "grant_type=client_credentials" \
  -d "client_id=CLIENT_ID" \
  -d "client_secret=CLIENT_SECRET" \
  -d "scope=cortex:chat"
```

Response:

```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIs...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "scope": "cortex:chat"
}
```

### 2. Client calls Cortex with the JWT

```bash
curl -X POST http://localhost:4000/api/chat \
  -H "Authorization: Bearer eyJ..." \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Hello!"}]}'
```

### 3. Cortex validates the JWT

```
AuthManager.authenticate(token, :thalamus)
  → ThalamusClient.introspect(token)
    → POST /oauth/introspect (with Basic auth)
    → Cache result in ETS (60s TTL)
  → Returns {:ok, %{user: nil, source: :thalamus, claims: %{...}}}
```

### 4. Claims are attached to the connection

```elixir
conn.assigns.cortex_user   # nil (no local user for JWT auth)
conn.assigns.auth_source   # :thalamus
conn.assigns.auth_claims   # %{"active" => true, "scope" => "...", ...}
```

---

## JWT Claims Reference

On successful introspection, Thalamus returns:

```json
{
  "active": true,
  "scope": "cortex:chat cortex:models:read",
  "client_id": "client_00000000-0000-0000-0000-000000000001",
  "token_type": "Bearer",
  "sub": "user_abc123",
  "user_id": "user_abc123",
  "username": "user_abc123",
  "email": "user@example.com",
  "organization_id": "660e8400-e29b-41d4-a716-446655440000",
  "exp": 1784561961,
  "iat": 1784558361,
  "domain_roles": [
    {
      "org_id": "660e8400-...",
      "domain": "nutrition",
      "role": "nutritionist",
      "scopes": ["food:analyze"]
    }
  ]
}
```

> ⚠️ For authorization decisions, use `domain_roles` — it is the canonical source for
> multi-tenant permissions. See [Thalamus docs](https://github.com/ZeaCl/thalamus/docs/index.md).

---

## Forwarding JWT (Recommended Pattern)

When a service calls Cortex on behalf of a user, **forward the user's JWT** instead of obtaining a new M2M token:

```
Mobile App → NutriSnaps API → Cortex
   JWT          JWT            JWT (same token)
```

Cortex validates the forwarded JWT and sees the original user's identity, `domain_roles`, and scopes. This enables per-user audit trails and authorization.

See [NutriSnaps Migration Guide](../NUTRISNAPS_MIGRATION.md) for a concrete example.

---

## Caching

`ThalamusClient` caches introspection results in an ETS table with a configurable TTL:

| Variable | Default | Description |
|---|---|---|
| `THALAMUS_CACHE_TTL` | `60` | Cache TTL in seconds |

Cache hits avoid network calls entirely. The cache key is a SHA256 hash of the token (raw JWTs are never stored in memory).

---

## Deprecation Warnings

When using `ctx_` API keys in `hybrid` mode, Cortex logs a deprecation warning (throttled to 1 per minute):

```
[warning] Using deprecated ctx_ API key. Migrate to Thalamus OAuth2 tokens.
```

---

## Error Reference

| Error | Meaning |
|---|---|
| `:inactive_token` | Token is valid but not active (expired, revoked) |
| `:invalid_credentials` | HTTP 401 — bad client_id or client_secret |
| `:timeout` | Introspect request exceeded 5 seconds |
| `:invalid_token` | Empty or non-string token |
| `:local_keys_not_allowed_in_thalamus_mode` | ctx_ key used in thalamus-only mode |

---

## See Also

- [Authentication](../AUTHENTICATION.md) — Full auth system docs
- [Configuration](../configuration.md) — Environment variables
- [Thalamus Docs](https://github.com/ZeaCl/thalamus/docs/index.md) — Auth service docs
- [Cerebelum Integration](https://github.com/ZeaCl/cerebelum/docs/guides/thalamus-integration.md) — Another ZEA service pattern
