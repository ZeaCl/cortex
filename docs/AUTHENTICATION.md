# Cortex Authentication System

## Overview

Cortex uses a **self-contained authentication system** inspired by OpenClaw. Client applications (like Allisbox) authenticate using **Cortex API keys**, and Cortex manages user credentials internally without exposing them to clients.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Client (Allisbox)                        │
│                                                                   │
│  - Uses Cortex API Key (ctx_abc123...)                          │
│  - No knowledge of AI provider credentials                       │
│  - Sends: Authorization: Bearer ctx_abc123...                   │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Cortex (AI Gateway)                         │
│                                                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  1. AuthenticateApiKey Middleware                         │  │
│  │     - Validates ctx_abc123... against cortex_api_keys     │  │
│  │     - Assigns cortex_user to conn.assigns                 │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                │                                  │
│                                ▼                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  2. ChatController                                        │  │
│  │     - Reads cortex_user from conn.assigns                 │  │
│  │     - Looks up user's provider credentials (OAuth/API)    │  │
│  │     - Uses user creds OR falls back to server creds       │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                │                                  │
│                                ▼                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  3. Provider (Claude, OpenAI, etc.)                       │  │
│  │     - Receives authenticated request                      │  │
│  │     - Uses user's Claude Pro subscription (via OAuth)     │  │
│  │     - OR uses server API keys as fallback                 │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Database Schema

### cortex_users
Local users of the Cortex gateway.

```elixir
field :username, :string  # e.g., "default", "my_cortex"
field :email, :string     # Optional
field :name, :string      # Optional

has_many :api_keys, CortexApiKey
has_many :credentials, UserCredential
```

### cortex_api_keys
API keys used by client applications to authenticate with Cortex.

```elixir
field :key, :string           # Format: "ctx_" + base64 (32+ chars)
field :name, :string          # e.g., "Allisbox Production"
field :expires_at, :utc_datetime
field :last_used_at, :utc_datetime
field :is_active, :boolean

belongs_to :user, CortexUser
```

**Key Generation:**
```elixir
CortexApiKey.generate_key()
# => "ctx_KF2Nhb1wZWot4X2EE1R9zduiW8KEf9Y8"
```

### user_credentials
Encrypted credentials for AI providers (OAuth tokens, API keys).

```elixir
field :provider, :string      # "anthropic_cli", "anthropic_api", "openai", etc.
field :auth_type, :string     # "oauth", "api_key", "token"
field :encrypted_data, :binary
field :expires_at, :utc_datetime
field :last_used_at, :utc_datetime
field :is_active, :boolean

belongs_to :user, CortexUser
```

## Setup Flow

### 1. Run Setup Wizard

```bash
mix cortex.setup
```

### 2. Choose Provider

The wizard detects Claude Code CLI credentials automatically:

```
Welcome to Cortex! Let's get you set up.

Setup mode:
  1. QuickStart (Recommended)
  2. Manual Configuration

> 1

Select your primary AI provider:
  1. Anthropic (Claude Code CLI) - Reuses existing Claude Code auth
  2. Anthropic (API Key)
  3. OpenAI
  ...

> 1
```

### 3. Save Credentials

Wizard:
- Creates a "default" CortexUser
- Saves provider credentials to `user_credentials`
- Generates a Cortex API key
- Displays the key for client configuration

```
✓ Found Claude Code credentials!
  Token type: oauth
  Expires: 2026-03-15 10:30:00

Use these credentials for Cortex? [Y/n] y

✓ Credentials saved to database!
✓ Generated Cortex API key

═══════════════════════════════════════
✓ Setup complete!
═══════════════════════════════════════

Your Cortex API Key:
  ctx_KF2Nhb1wZWot4X2EE1R9zduiW8KEf9Y8

⚠ Save this key somewhere safe - you won't see it again!

Use this key in your client applications (like Allisbox):
  Authorization: Bearer ctx_KF2Nhb1wZWot4X2EE1R9zduiW8KEf9Y8
```

## Client Usage (Allisbox)

### Configuration

Add to Allisbox `.env`:

```bash
CORTEX_URL=http://localhost:4000
CORTEX_API_KEY=ctx_KF2Nhb1wZWot4X2EE1R9zduiW8KEf9Y8
```

### API Request

```javascript
const response = await fetch('http://localhost:4000/api/chat', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ctx_KF2Nhb1wZWot4X2EE1R9zduiW8KEf9Y8'
  },
  body: JSON.stringify({
    messages: [
      { role: 'user', content: 'Hello!' }
    ],
    model: 'claude-3-5-sonnet-20241022'
  })
})
```

## Authentication Flow

### Request Processing

1. **Client sends request** with `Authorization: Bearer ctx_abc123...`

2. **AuthenticateApiKey middleware:**
   ```elixir
   def call(conn, _opts) do
     with {:ok, api_key} <- extract_api_key(conn),
          {:ok, user} <- Users.authenticate_by_api_key(api_key) do
       conn
       |> assign(:cortex_user, user)
       |> assign(:authenticated_via, :api_key)
     else
       {:error, :missing_authorization} ->
         # Allow request (backward compatibility)
         conn

       {:error, reason} ->
         # 401 Unauthorized
         send_resp(conn, 401, ...)
         |> halt()
     end
   end
   ```

3. **ChatController extracts user:**
   ```elixir
   def create(conn, %{"messages" => messages}) do
     cortex_user = Map.get(conn.assigns, :cortex_user)
     # ...
     dispatch_and_stream(conn, messages, opts, cortex_user, start_time)
   end
   ```

4. **Credential lookup with fallback:**
   ```elixir
   defp dispatch_and_stream(conn, messages, opts, nil, start_time) do
     # No user → use server API keys
     dispatch_with_server_credentials(conn, messages, opts, start_time)
   end

   defp dispatch_and_stream(conn, messages, opts, user, start_time) do
     case try_user_credentials(user, messages, opts) do
       {:ok, stream} ->
         # Use user's credentials
         stream_response(conn, stream, start_time)

       {:fallback, reason} ->
         # Fall back to server credentials
         dispatch_with_server_credentials(conn, messages, opts, start_time)
     end
   end
   ```

## Backward Compatibility

The system is **100% backward compatible**:

- **Requests without Authorization header** → Use server API keys (original behavior)
- **Requests with invalid API key** → 401 Unauthorized
- **Requests with valid API key but no credentials** → Fallback to server API keys
- **Requests with valid API key and credentials** → Use user's credentials

## Security Considerations

### Current Implementation (TODO)

Credentials are currently stored as **plain JSON** in the database:

```elixir
defp encrypt_credentials(data) do
  # TODO: Implement proper encryption
  Jason.encode!(data)
end
```

### Planned Improvements

1. **Encrypt credentials** using Cloak or similar
2. **Add rate limiting** per API key
3. **Add scopes/permissions** to API keys
4. **Implement credential refresh** for OAuth tokens
5. **Add audit logging** for credential usage

## API Key Management

### List User's API Keys

```elixir
iex> Users.list_user_api_keys(user_id)
[
  %CortexApiKey{
    key: "ctx_KF2Nhb1wZWot4X2EE1R9zduiW8KEf9Y8",
    name: "Setup Wizard Key",
    is_active: true,
    ...
  }
]
```

### Create New API Key

```elixir
iex> Users.create_api_key(user_id, %{name: "Production Key"})
{:ok, %CortexApiKey{key: "ctx_..."}}
```

### Revoke API Key

```elixir
iex> Users.revoke_api_key(api_key_id)
{:ok, %CortexApiKey{is_active: false}}
```

### Preview API Key (Safe Display)

```elixir
iex> Users.preview_api_key("ctx_KF2Nhb1wZWot4X2EE1R9zduiW8KEf9Y8")
"ctx_KF2...f9Y8"
```

## Testing

### Manual Testing

```bash
# Start Cortex
cd /Users/dev/Documents/zea/cortex/cortex_community
mix phx.server

# Test with API key
curl -X POST http://localhost:4000/api/chat \
  -H "Authorization: Bearer ctx_KF2Nhb1wZWot4X2EE1R9zduiW8KEf9Y8" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Hello!"}],
    "model": "claude-3-5-sonnet-20241022"
  }'

# Test without API key (should use server credentials)
curl -X POST http://localhost:4000/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Hello!"}]
  }'

# Test with invalid API key (should return 401)
curl -X POST http://localhost:4000/api/chat \
  -H "Authorization: Bearer ctx_invalid" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## Next Steps

1. ✅ **Database migrations** - Complete
2. ✅ **Schemas** - Complete
3. ✅ **Context modules** - Complete
4. ✅ **Authentication middleware** - Complete
5. ✅ **ChatController integration** - Complete
6. ✅ **Setup wizard API key generation** - Complete
7. 🚧 **OAuth implementation** for claude.ai (coming soon)
8. 🚧 **Credential encryption** (security improvement)
9. 🚧 **API key management endpoints** (list, revoke, create)
10. 🚧 **Allisbox integration** (configure to use Cortex API key)
