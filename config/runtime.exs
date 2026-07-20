import Config
import Dotenvy

# Load .env file if it exists (development/local)
# In production, use system environment variables instead
source!([".env", System.get_env()])

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/cortex_community start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :cortex_community, CortexCommunityWeb.Endpoint, server: true
end

# CortexCore auto-configures workers from environment variables
# No need to manually configure workers - they are auto-detected from:
# - OPENAI_API_KEYS
# - ANTHROPIC_API_KEYS
# - GEMINI_API_KEYS
# - GROQ_API_KEYS
# - TAVILY_API_KEY  (NEW!)
# - etc.

config :cortex_core,
  worker_pool_strategy: String.to_atom(System.get_env("WORKER_POOL_STRATEGY", "local_first"))

# ---------------------------------------------------------------------------
# Auth: Thalamus OAuth2 Integration
# ---------------------------------------------------------------------------

auth_mode =
  case System.get_env("AUTH_MODE", "hybrid") do
    "local" -> :local
    "thalamus" -> :thalamus
    _ -> :hybrid
  end

config :cortex_community, :auth,
  mode: auth_mode,
  thalamus_introspect_url:
    System.get_env("THALAMUS_INTROSPECT_URL", "https://auth.zea.cl/oauth/introspect"),
  thalamus_client_id: System.get_env("THALAMUS_CLIENT_ID"),
  thalamus_client_secret: System.get_env("THALAMUS_CLIENT_SECRET"),
  thalamus_cache_ttl: String.to_integer(System.get_env("THALAMUS_CACHE_TTL", "60"))

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :cortex_community, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :cortex_community, CortexCommunityWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # Database configuration via DATABASE_URL (standard for Elixir releases)
  if database_url = System.get_env("DATABASE_URL") do
    config :cortex_community, CortexCommunity.Repo,
      url: database_url,
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
      socket_options: System.get_env("DB_SOCKET_OPTIONS") || []
  end
end
