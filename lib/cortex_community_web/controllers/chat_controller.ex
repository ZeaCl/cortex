# lib/cortex_community_web/controllers/chat_controller.ex
defmodule CortexCommunityWeb.ChatController do
  use CortexCommunityWeb, :controller
  require Logger

  @cortex_core Application.compile_env(:cortex_community, :cortex_core, CortexCore)

  alias CortexCommunity.Clients.ClaudeOAuthClient
  alias CortexCommunity.Credentials
  alias CortexCommunity.StatsCollector

  # Authenticate API key and assign user to conn.assigns.cortex_user
  plug CortexCommunityWeb.Plugs.AuthenticateApiKey

  @doc """
  Main chat endpoint - handles streaming responses from AI providers
  """
  def create(conn, %{"messages" => messages} = params) when is_list(messages) do
    # Track request start
    start_time = System.monotonic_time(:millisecond)

    # Extract options
    opts = extract_options(params)

    # Extract authenticated user from middleware (if present)
    cortex_user = Map.get(conn.assigns, :cortex_user)

    # Log request
    Logger.info(
      "Chat request: user=#{inspect(cortex_user && cortex_user.username)}, messages=#{length(messages)}"
    )

    conn
    |> put_resp_header("content-type", "text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("connection", "keep-alive")
    # For nginx
    |> put_resp_header("x-accel-buffering", "no")
    |> dispatch_and_stream(messages, opts, cortex_user, start_time)
  end

  def create(conn, %{"messages" => _}) do
    error_response(conn, 400, "Messages must be an array")
  end

  def create(conn, _params) do
    error_response(conn, 400, "Missing required field: messages")
  end

  # Private functions

  defp dispatch_and_stream(conn, messages, opts, nil, start_time) do
    # No authenticated user → use server API keys (original behavior)
    Logger.debug("No authenticated user - using server API keys")
    dispatch_with_server_credentials(conn, messages, opts, start_time)
  end

  defp dispatch_and_stream(conn, messages, opts, %CortexCommunity.CortexUser{} = user, start_time) do
    # Authenticated user → try user credentials first, fallback to server if not available
    case try_user_credentials(user, messages, opts) do
      {:ok, stream} ->
        Logger.info("✓ Using user credentials for user=#{user.username}")
        StatsCollector.track_request(:started)

        conn
        |> send_chunked(200)
        |> stream_response(stream, start_time)

      {:fallback, reason} ->
        Logger.warning(
          "⚠️  OAuth falló (#{reason}), usando credenciales del servidor (Gemini/Groq)"
        )

        dispatch_with_server_credentials(conn, messages, opts, start_time)
    end
  end

  # Try to use user's configured credentials
  defp try_user_credentials(%CortexCommunity.CortexUser{id: user_id} = user, messages, opts) do
    case determine_provider(opts) do
      nil ->
        # Non-anthropic worker requested — use server pool (groq, gemini, etc.)
        {:fallback, "non-anthropic provider requested, routing to server pool"}

      provider ->
        case Credentials.get_credentials(user_id, provider) do
          {:ok, user_creds} ->
            Logger.debug("Found credentials for user=#{user.username}, provider=#{provider}")
            use_user_credentials(user_creds, messages, opts)

          {:error, :not_found} ->
            {:fallback, "no credentials configured"}

          {:error, :expired} ->
            {:fallback, "credentials expired"}
        end
    end
  end

  defp determine_provider(opts) do
    requested_worker = Keyword.get(opts, :provider)
    model = Keyword.get(opts, :model, "")

    cond do
      # Specific non-anthropic worker requested → fall back to server pool
      is_binary(requested_worker) and not String.contains?(requested_worker, "anthropic") -> nil
      String.contains?(model, "claude") -> "anthropic_cli"
      String.contains?(model, "gpt") -> "openai"
      String.contains?(model, "gemini") -> "google"
      # default: usar server pool (gemini/groq)
      true -> nil
    end
  end

  # Use user's credentials instead of server API keys
  # Pattern match for OAuth (accepts both atom and string)
  defp use_user_credentials(%{type: type} = creds, messages, opts)
       when type in [:oauth, "oauth"] do
    Logger.debug("Using OAuth token for provider=#{creds.provider}")

    # Check if credentials are still valid
    if ClaudeOAuthClient.credentials_valid?(creds) do
      # Make request using OAuth token
      case ClaudeOAuthClient.chat(messages, creds, opts) do
        {:ok, stream} ->
          Logger.info("✓ Successfully using user's Claude Pro subscription via OAuth")
          {:ok, stream}

        {:error, reason} ->
          Logger.error("OAuth request failed: #{inspect(reason)}")
          {:fallback, "oauth request failed: #{inspect(reason)}"}
      end
    else
      Logger.warning("OAuth credentials expired")
      {:fallback, "credentials expired"}
    end
  end

  defp use_user_credentials(%{api_key: api_key} = creds, messages, opts) do
    Logger.debug("Using user API key for provider=#{creds.provider}")

    # Inject user's API key into options
    opts_with_user_key = Keyword.put(opts, :api_key, api_key)

    case @cortex_core.chat(messages, opts_with_user_key) do
      {:ok, stream} -> {:ok, stream}
      {:error, _} -> {:fallback, "user api key failed"}
    end
  end

  defp use_user_credentials(_creds, _messages, _opts) do
    {:fallback, "unsupported credential type"}
  end

  # Original dispatch logic (unchanged, now called when no user_id or fallback)
  defp dispatch_with_server_credentials(conn, messages, opts, start_time) do
    case @cortex_core.chat(messages, opts) do
      {:ok, stream} ->
        # Track successful dispatch
        StatsCollector.track_request(:started)

        conn
        |> send_chunked(200)
        |> stream_response(stream, start_time)

      {:error, :no_workers_available} ->
        StatsCollector.track_request(:no_workers)
        error_response(conn, 503, "No AI workers available at this moment")

      {:error, {:all_workers_failed, details}} ->
        StatsCollector.track_request(:all_failed)
        Logger.error("All workers failed: #{inspect(details)}")

        conn
        |> put_status(500)
        |> json(%{
          error: true,
          message: "All AI providers failed",
          details: format_error_details(details),
          timestamp: DateTime.utc_now()
        })

      {:error, reason} ->
        StatsCollector.track_request(:error)
        Logger.error("Chat request failed: #{inspect(reason)}")
        error_response(conn, 500, "Internal server error")
    end
  end

  defp stream_response(conn, stream, start_time) do
    final_conn =
      Enum.reduce_while(stream, {conn, 0, %{}}, fn
        {:stream_done, ratelimit_info}, {acc_conn, token_count, _} ->
          {:cont, {acc_conn, token_count, ratelimit_info}}

        chunk, {acc_conn, token_count, ratelimit_info} ->
          case send_sse_chunk(acc_conn, chunk) do
            {:ok, new_conn} ->
              {:cont, {new_conn, token_count + estimate_tokens(chunk), ratelimit_info}}

            {:error, _reason} ->
              {:halt, {acc_conn, token_count, ratelimit_info}}
          end
      end)
      |> case do
        {final_conn, token_count, ratelimit_info} ->
          duration = System.monotonic_time(:millisecond) - start_time
          {:ok, conn_with_done} = send_sse_done(final_conn, ratelimit_info)

          StatsCollector.track_request(:completed, %{
            duration: duration,
            tokens: token_count
          })

          Logger.info("Stream completed: #{token_count} tokens in #{duration}ms")
          conn_with_done
      end

    final_conn
  rescue
    error ->
      Logger.error("Stream processing error: #{inspect(error)}")
      StatsCollector.track_request(:stream_error)
      conn
  catch
    :exit, _ ->
      StatsCollector.track_request(:stream_exit)
      conn

    _, _ ->
      StatsCollector.track_request(:stream_error)
      conn
  end

  defp send_sse_done(conn, ratelimit_info) do
    model = Map.get(ratelimit_info, "model")
    worker = Map.get(ratelimit_info, "worker")
    failover = Map.get(ratelimit_info, "failover", [])
    clean_info = Map.drop(ratelimit_info, ["model", "worker", "failover"])

    base = %{"done" => true}
    base = if is_binary(model) and model != "", do: Map.put(base, "model", model), else: base
    base = if is_binary(worker) and worker != "", do: Map.put(base, "worker", worker), else: base
    base = if failover != [], do: Map.put(base, "failover", failover), else: base

    payload =
      if map_size(clean_info) > 0 do
        Jason.encode!(Map.put(base, "ratelimit", clean_info))
      else
        Jason.encode!(base)
      end

    case Plug.Conn.chunk(conn, "event: done\ndata: #{payload}\n\n") do
      {:ok, conn} -> {:ok, conn}
      error -> error
    end
  end

  defp send_sse_chunk(conn, chunk) when is_binary(chunk) do
    # Format as SSE
    sse_data = "data: #{Jason.encode!(%{content: chunk})}\n\n"

    case Plug.Conn.chunk(conn, sse_data) do
      {:ok, conn} -> {:ok, conn}
      error -> error
    end
  end

  defp send_sse_chunk(conn, _), do: {:ok, conn}

  defp extract_options(params) do
    []
    |> maybe_add_option(:provider, params["provider"])
    |> maybe_add_option(:model, params["model"])
    |> maybe_add_option(:temperature, params["temperature"])
    |> maybe_add_option(:max_tokens, params["max_tokens"])
    |> maybe_add_option(:stream, params["stream"])
    |> maybe_add_option(:top_p, params["top_p"])
    |> maybe_add_option(:frequency_penalty, params["frequency_penalty"])
    |> maybe_add_option(:presence_penalty, params["presence_penalty"])
    |> maybe_add_option(:stop, params["stop"])
    |> maybe_add_option(:user, params["user"])
  end

  defp maybe_add_option(opts, _key, nil), do: opts

  defp maybe_add_option(opts, key, value) do
    Keyword.put(opts, key, value)
  end

  defp error_response(conn, status, message) do
    conn
    |> put_status(status)
    |> json(%{
      error: true,
      message: message,
      timestamp: DateTime.utc_now()
    })
  end

  defp format_error_details(details) when is_binary(details), do: details

  defp format_error_details(details) when is_list(details) do
    Enum.map_join(details, "; ", fn
      {provider, error} -> "#{provider}: #{error}"
      error -> to_string(error)
    end)
  end

  defp format_error_details(details), do: inspect(details)

  defp estimate_tokens(text) when is_binary(text) do
    # Rough estimation: ~4 characters per token
    div(String.length(text), 4)
  end

  defp estimate_tokens(_), do: 0
end
