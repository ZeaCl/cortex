defmodule Mix.Tasks.Cortex.Setup.Thalamus do
  @moduledoc """
  Registra Cortex como OAuth2 client en Thalamus.

  Esto es necesario para que Cortex pueda:
  - Validar JWT tokens vía `/oauth/introspect`
  - Obtener tokens M2M vía `client_credentials`
  - Resolver secrets de AI providers por usuario/org

  ## Uso

      mix cortex.setup.thalamus
      mix cortex.setup.thalamus --url=http://auth.zea.localhost
      mix cortex.setup.thalamus --org=zea

  ## Qué hace

  1. Detecta la URL de Thalamus (config, env, o flag --url)
  2. Verifica que el usuario esté autenticado (ZEA_PAT o config)
  3. Crea un OAuth2 client `cortex` en Thalamus
  4. Guarda THALAMUS_CLIENT_ID y THALAMUS_CLIENT_SECRET en .env
  """

  use Mix.Task

  @shortdoc "Registra Cortex como OAuth2 client en Thalamus"

  @client_name "cortex"
  @client_type "confidential"
  @client_grants "client_credentials"
  @client_scopes "cortex:chat"

  @impl Mix.Task
  def run(args) do
    opts = parse_args(args)
    Mix.Task.run("app.start")

    IO.puts("\n🔄 Registrando Cortex como OAuth2 client en Thalamus...\n")

    # 1. Determinar Thalamus URL
    thalamus_url = resolve_thalamus_url(opts)
    IO.puts("   Thalamus: #{thalamus_url}")

    # 2. Obtener token de auth
    case resolve_token() do
      nil ->
        IO.puts("""

        ❌ No autenticado. Necesitás autenticarte primero:

            zea thalamus auth login

        O configurá manualmente:

            export ZEA_PAT=<tu-token>

        Y volvé a ejecutar:

            mix cortex.setup.thalamus
        """)

      token ->
        IO.puts("   Token:    ✅ encontrado")

        # 3. Verificar si el client ya existe
        case find_existing_client(thalamus_url, token) do
          {:ok, client_id, client_secret} ->
            IO.puts("""

            ⚠️  El client '#{@client_name}' ya existe en Thalamus.
                Client ID: #{client_id}

            ¿Querés rotar el secret?
            """)

            if confirm?("Rotar client secret? [y/N]") do
              rotate_and_save(thalamus_url, token, client_id)
            else
              save_to_env(client_id, client_secret)
              print_success(client_id)
            end

          {:not_found} ->
            # 4. Crear el client
            create_and_save(thalamus_url, token, opts)

          {:error, reason} ->
            IO.puts("\n❌ Error verificando client existente: #{reason}")
        end
    end
  end

  # ── Argument parsing ────────────────────────────────────────

  defp parse_args(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [url: :string, org: :string],
        aliases: [u: :url, o: :org]
      )

    opts
  end

  # ── Thalamus URL resolution ─────────────────────────────────

  defp resolve_thalamus_url(opts) do
    opts[:url] ||
      System.get_env("ZEA_API_URL") ||
      System.get_env("THALAMUS_API_URL") ||
      read_config("apiUrl") ||
      "https://auth.zea.cl"
  end

  defp read_config(key) do
    config_file = Path.join(System.user_home!(), ".config/zea/config.json")

    case File.read(config_file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, config} -> config[key]
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # ── Token resolution ────────────────────────────────────────

  defp resolve_token do
    System.get_env("ZEA_PAT") ||
      System.get_env("THALAMUS_PAT") ||
      System.get_env("ZEA_TOKEN") ||
      read_config("token")
  end

  # ── Thalamus API calls ──────────────────────────────────────

  defp find_existing_client(thalamus_url, token) do
    url = "#{thalamus_url}/api/clients"

    case Req.get(url,
           headers: auth_headers(token),
           receive_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        clients = body["data"] || body["clients"] || []
        existing = Enum.find(clients, &(&1["name"] == @client_name))

        if existing do
          {:ok, existing["id"], existing["client_secret"]}
        else
          {:not_found}
        end

      {:ok, %Req.Response{status: 401}} ->
        {:error, "Token inválido o expirado. Ejecutá: zea thalamus auth login"}

      {:ok, %Req.Response{status: status}} ->
        {:error, "Thalamus respondió HTTP #{status}"}

      {:error, error} ->
        {:error, "No se puede conectar a #{thalamus_url}: #{inspect(error)}"}
    end
  end

  defp create_and_save(thalamus_url, token, opts) do
    url = "#{thalamus_url}/api/clients"

    # Obtener organization_id del userinfo o del flag --org
    org_id = opts[:org] || resolve_org_id(thalamus_url, token)

    if !org_id do
      IO.puts("\n❌ No se pudo determinar la organización.")
      IO.puts("   Especificá una con: mix cortex.setup.thalamus --org=<slug>")
      IO.puts("   O authentícate primero: zea thalamus auth login")
    else
      body = %{
        name: @client_name,
        client_type: @client_type,
        redirect_uris: [],
        grant_types: @client_grants,
        scopes: @client_scopes,
        organization_id: org_id
      }

      IO.puts("   Creando client '#{@client_name}'...")

      case Req.post(url,
             headers: auth_headers(token),
             json: body,
             receive_timeout: 10_000
           ) do
        {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
          client = body["data"] || body
          client_id = client["id"] || client["client_id"]
          client_secret = client["client_secret"]

          if client_id && client_secret do
            save_to_env(client_id, client_secret)
            save_to_config(thalamus_url)
            print_new_client_success(client_id, client_secret)
          else
            IO.puts("\n❌ Respuesta inesperada de Thalamus: #{inspect(body)}")
          end

        {:ok, %Req.Response{status: 401}} ->
          IO.puts("\n❌ No autorizado. Verificá que tengas permisos de admin en la organización.")

        {:ok, %Req.Response{status: 422, body: body}} ->
          errors = body["errors"] || body["error"] || "Validation error"
          IO.puts("\n❌ Error de validación: #{inspect(errors)}")

        {:ok, %Req.Response{status: status}} ->
          IO.puts("\n❌ Thalamus respondió HTTP #{status}")

        {:error, error} ->
          IO.puts("\n❌ Error de conexión: #{inspect(error)}")
      end
    end
  end

  defp rotate_and_save(thalamus_url, token, client_id) do
    url = "#{thalamus_url}/api/clients/#{client_id}/rotate-secret"

    case Req.post(url,
           headers: auth_headers(token),
           receive_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        client = body["data"] || body
        client_secret = client["client_secret"]

        if client_secret do
          save_to_env(client_id, client_secret)
          save_to_config(thalamus_url)
          print_new_client_success(client_id, client_secret)
        end

      {:ok, %Req.Response{status: status}} ->
        IO.puts("\n❌ Error rotando secret: HTTP #{status}")

      {:error, error} ->
        IO.puts("\n❌ Error de conexión: #{inspect(error)}")
    end
  end

  # ── Persistence ─────────────────────────────────────────────

  defp save_to_env(client_id, client_secret) do
    env_file = ".env"
    env_content = File.exists?(env_file) && File.read!(env_file) || ""

    new_lines = [
      "# Cortex — Thalamus OAuth2 client (generado por mix cortex.setup.thalamus)",
      "THALAMUS_CLIENT_ID=#{client_id}",
      "THALAMUS_CLIENT_SECRET=#{client_secret}"
    ]

    updated =
      if String.contains?(env_content, "THALAMUS_CLIENT_ID=") do
        # Replace existing values
        env_content
        |> String.replace(~r/^THALAMUS_CLIENT_ID=.*$/m, "THALAMUS_CLIENT_ID=#{client_id}")
        |> String.replace(~r/^THALAMUS_CLIENT_SECRET=.*$/m, "THALAMUS_CLIENT_SECRET=#{client_secret}")
      else
        # Append to .env
        trimmed = String.trim_trailing(env_content)
        if trimmed == "", do: Enum.join(new_lines, "\n"), else: trimmed <> "\n" <> Enum.join(new_lines, "\n")
      end

    File.write!(env_file, updated)
    IO.puts("\n   ✅ Guardado en .env")
  end

  defp save_to_config(thalamus_url) do
    config_file = Path.join(System.user_home!(), ".config/zea/config.json")

    config =
      case File.read(config_file) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, cfg} -> cfg
            _ -> %{}
          end

        _ ->
          %{}
      end

    updated = Map.put(config, "apiUrl", thalamus_url)

    File.mkdir_p!(Path.dirname(config_file))
    File.write!(config_file, Jason.encode!(updated, pretty: true))
  end

  # ── Output ──────────────────────────────────────────────────

  defp print_new_client_success(client_id, client_secret) do
    IO.puts("""

    ╔══════════════════════════════════════════════════════════╗
    ║  ✅ Cortex registrado como OAuth2 client en Thalamus    ║
    ╚══════════════════════════════════════════════════════════╝

      Client ID:     #{client_id}
      Client Secret: #{client_secret}

    ⚠️  GUARDÁ EL CLIENT SECRET — no se mostrará de nuevo.

    Configuración guardada en .env:

      THALAMUS_CLIENT_ID=#{client_id}
      THALAMUS_CLIENT_SECRET=#{client_secret}

    Para verificar:

      zea thalamus client show #{client_id}
      zea thalamus client validate #{client_id}

    """)
  end

  defp print_success(client_id) do
    IO.puts("""

    ✅ Cortex ya está registrado. Client ID: #{client_id}

    Para verificar:

      zea thalamus client show #{client_id}

    """)
  end

  # ── Helpers ─────────────────────────────────────────────────

  defp resolve_org_id(thalamus_url, token) do
    # 1. Check --org flag (passed via opts, but we need it here)
    # For now, resolve from userinfo
    case Req.get("#{thalamus_url}/oauth/userinfo",
           headers: auth_headers(token),
           receive_timeout: 5_000
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        org = body["organization"] || %{}
        org["id"] || body["organization_id"]

      _ ->
        nil
    end
  end

  defp auth_headers(token) do
    [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]
  end

  defp confirm?(prompt) do
    IO.write("#{prompt} ")
    input = IO.gets("") |> String.trim() |> String.downcase()

    input in ["y", "yes", "s", "si", "sí"]
  end
end
