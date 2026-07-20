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
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
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
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :cortex_community, CortexCommunityWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :cortex_community, CortexCommunityWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
