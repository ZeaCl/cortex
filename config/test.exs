import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :cortex_community, CortexCommunityWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "wnIerl79Hs+9XqrIYgBNqV6U4jjLpU867gerOBGn/pMT+0l0UM8ND2KYftLRZRR+",
  server: false

# Use Mox mocks instead of real implementations in tests
config :cortex_community, :cortex_core, CortexCore.Mock
config :cortex_community, :users_module, CortexCommunity.Users.Mock

# Force local auth mode in tests (no Thalamus dependency)
# Set as system env var so runtime.exs picks it up (runs after compile-time config)
System.put_env("AUTH_MODE", "local")

config :cortex_community, :auth, mode: :local

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
