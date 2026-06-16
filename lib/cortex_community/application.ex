# lib/cortex_community/application.ex
defmodule CortexCommunity.Application do
  @moduledoc """
  Main application supervisor for Cortex Community.
  Starts all necessary processes including the web endpoint and Cortex Core.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Print startup banner
    print_banner()

    # Configure Cortex Core from environment
    _cortex_config = configure_cortex()

    children = [
      # Start the Ecto repository
      CortexCommunity.Repo,

      # Start Telemetry supervisor
      CortexCommunityWeb.Telemetry,

      # Start CortexCore supervisor
      %{
        id: CortexCore,
        start:
          {CortexCore, :start_link,
           [
             [
               strategy:
                 String.to_existing_atom(System.get_env("WORKER_POOL_STRATEGY", "local_first")),
               check_interval: :disabled
             ]
           ]},
        type: :supervisor
      },

      # Start model discovery + ranking selector
      CortexCommunity.ModelSelector,

      # Start simple stats collector
      CortexCommunity.StatsCollector,

      # Start the PubSub system
      {Phoenix.PubSub, name: CortexCommunity.PubSub},

      # Start Finch for HTTP client
      {Finch, name: CortexCommunity.Finch},

      # Start the Endpoint (last)
      CortexCommunityWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: CortexCommunity.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("🚀 Cortex Community started successfully!")
        # Configure workers synchronously to ensure they're ready on startup
        Task.start(fn ->
          :timer.sleep(500)

          try do
            CortexCore.Workers.Supervisor.configure_initial_workers(
              CortexCore.Workers.Registry,
              model_resolver: &CortexCommunity.ModelSelector.get_model/1
            )

            configure_worker_capabilities()
            maybe_register_anthropic_oauth_worker()
            maybe_register_qwen_oauth_worker()
          rescue
            e -> Logger.error("Failed to configure workers: #{inspect(e)}")
          end
        end)

        # Auto-setup default user and OAuth credentials on startup
        Task.start(fn ->
          :timer.sleep(1000)
          auto_setup()
        end)

        print_status()
        {:ok, pid}

      error ->
        Logger.error("Failed to start Cortex Community: #{inspect(error)}")
        error
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    CortexCommunityWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  @worker_capabilities %{
    "anthropic-primary" => [:chat, :tools, :reasoning],
    "anthropic-oauth-local" => [:chat, :tools, :reasoning],
    "gemini-primary" => [:chat, :tools, :long_context, :vision],
    "gemini-pro-25-primary" => [:chat, :tools, :long_context, :vision],
    "groq-primary" => [:chat, :tools, :fast],
    "openai-primary" => [:chat, :tools, :vision],
    "qwen-oauth-local" => [:chat, :tools, :vision, :fast],
    "xai-primary" => [:chat],
    "cohere-primary" => [:chat],
    "ollama-local" => [:chat],
    "tavily-primary" => [:search],
    "serper-primary" => [:search],
    "brave-primary" => [:search],
    "pubmed-primary" => [:search],
    "duckduckgo-primary" => [:search]
  }

  defp configure_worker_capabilities do
    pool = CortexCore.Workers.Pool

    Enum.each(@worker_capabilities, fn {worker_name, caps} ->
      CortexCore.Workers.Pool.set_capabilities(pool, worker_name, caps)
    end)

    Logger.info("Worker capabilities configured")
  end

  defp maybe_register_anthropic_oauth_worker do
    alias CortexCommunity.Auth.ClaudeCliReader
    alias CortexCommunity.Workers.AnthropicOAuthWorker

    case ClaudeCliReader.read_credentials() do
      {:ok, creds} ->
        if ClaudeCliReader.valid?(creds) do
          worker =
            AnthropicOAuthWorker.new(
              name: "anthropic-oauth-local",
              credentials: creds,
              timeout: 60_000
            )

          case CortexCore.Workers.Registry.register(
                 CortexCore.Workers.Registry,
                 "anthropic-oauth-local",
                 worker
               ) do
            :ok ->
              CortexCore.Workers.Pool.set_capabilities(
                CortexCore.Workers.Pool,
                "anthropic-oauth-local",
                [:chat, :tools, :reasoning]
              )

              Logger.info("✅ anthropic-oauth-local registered (Claude Pro Max)")

            {:error, :already_registered} ->
              Logger.debug("anthropic-oauth-local already registered")

            error ->
              Logger.warning("Could not register anthropic-oauth-local: #{inspect(error)}")
          end
        else
          Logger.warning(
            "Claude OAuth credentials expired — anthropic-oauth-local not registered"
          )
        end

      {:error, :not_found} ->
        Logger.debug("No Claude CLI credentials found — skipping anthropic-oauth-local")

      {:error, reason} ->
        Logger.warning("Could not read Claude credentials: #{inspect(reason)}")
    end
  end

  defp maybe_register_qwen_oauth_worker do
    alias CortexCommunity.Auth.QwenCredentialReader
    alias CortexCommunity.Workers.QwenOAuthWorker

    case QwenCredentialReader.read_credentials() do
      {:ok, creds} ->
        if QwenCredentialReader.valid?(creds) do
          worker =
            QwenOAuthWorker.new(
              name: "qwen-oauth-local",
              access_token: creds.access_token,
              resource_url: creds.resource_url,
              timeout: 30_000
            )

          case CortexCore.Workers.Registry.register(
                 CortexCore.Workers.Registry,
                 "qwen-oauth-local",
                 worker
               ) do
            :ok ->
              CortexCore.Workers.Pool.set_capabilities(
                CortexCore.Workers.Pool,
                "qwen-oauth-local",
                [:chat, :tools, :vision, :fast]
              )

              Logger.info("✅ qwen-oauth-local registered (Qwen Code)")

            {:error, :already_registered} ->
              Logger.debug("qwen-oauth-local already registered")

            error ->
              Logger.warning("Could not register qwen-oauth-local: #{inspect(error)}")
          end
        else
          Logger.warning("Qwen OAuth credentials expired — qwen-oauth-local not registered")
        end

      {:error, :not_found} ->
        Logger.debug("No Qwen credentials found — skipping qwen-oauth-local")

      {:error, reason} ->
        Logger.warning("Could not read Qwen credentials: #{inspect(reason)}")
    end
  end

  defp configure_cortex do
    # Read configuration from environment
    strategy =
      case System.get_env("WORKER_POOL_STRATEGY", "local_first") do
        "round_robin" -> :round_robin
        "least_used" -> :least_used
        "random" -> :random
        _ -> :local_first
      end

    [strategy: strategy]
  end

  defp print_banner do
    banner = """

    ╔═══════════════════════════════════════════════════════════╗
    ║                                                           ║
    ║      ░█████╗░░█████╗░██████╗░████████╗███████╗██╗░░██╗  ║
    ║      ██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝╚██╗██╔╝  ║
    ║      ██║░░╚═╝██║░░██║██████╔╝░░░██║░░░█████╗░░░╚███╔╝░  ║
    ║      ██║░░██╗██║░░██║██╔══██╗░░░██║░░░██╔══╝░░░██╔██╗░  ║
    ║      ╚█████╔╝╚█████╔╝██║░░██║░░░██║░░░███████╗██╔╝╚██╗  ║
    ║      ░╚════╝░░╚════╝░╚═╝░░╚═╝░░░╚═╝░░░╚══════╝╚═╝░░╚═╝  ║
    ║                                                           ║
    ║               Community Edition v#{version()}            ║
    ║                  Powered by Cortex Core                  ║
    ╚═══════════════════════════════════════════════════════════╝
    """

    IO.puts(banner)
  end

  defp print_status do
    workers = CortexCore.list_workers()

    IO.puts("\n📊 System Status:")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    IO.puts("🔧 Workers configured: #{length(workers)}")

    Enum.each(workers, fn worker ->
      IO.puts("   • #{worker.name} (#{worker.type})")
    end)

    port = Application.get_env(:cortex_community, CortexCommunityWeb.Endpoint)[:http][:port]
    IO.puts("\n🌐 API available at: http://localhost:#{port}")
    IO.puts("📚 Documentation at: http://localhost:#{port}/docs")
    IO.puts("💓 Health check at: http://localhost:#{port}/health")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
  end

  defp auto_setup do
    alias CortexCommunity.Users

    # Crear usuario default si no existe
    user =
      case Users.get_user_by_username("default") do
        nil ->
          case Users.create_user(%{username: "default", name: "Default User"}) do
            {:ok, u} -> u
            _ -> nil
          end

        existing ->
          existing
      end

    if user do
      api_key_value = get_api_key_value(user.id)
      Logger.info("✅ Gateway listo — API Key: #{Users.preview_api_key(api_key_value)}")
    end
  end

  defp get_api_key_value(user_id) do
    case CortexCommunity.Users.get_or_create_api_key(user_id, %{name: "default"}) do
      {:ok, api_key} ->
        File.write("/tmp/cortex_api_key.txt", api_key.key)
        File.chmod("/tmp/cortex_api_key.txt", 0o600)
        key_preview = CortexCommunity.Users.preview_api_key(api_key.key)
        Logger.info("🔑 API key lista: #{key_preview}")
        api_key.key

      _ ->
        nil
    end
  end

  defp version do
    Application.spec(:cortex_community, :vsn) |> to_string()
  end
end
