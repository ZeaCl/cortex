defmodule CortexCommunity.Auth.ThalamusClient do
  @moduledoc """
  Client for Thalamus OAuth2 token introspection.

  Validates JWT tokens against the Thalamus `/oauth/introspect` endpoint
  using HTTP Basic authentication (client_id:client_secret). Results are
  cached in ETS for a configurable TTL (default 60 seconds) to avoid
  redundant network calls.

  ## Environment Variables

    * `THALAMUS_INTROSPECT_URL` — introspection endpoint URL
      (default: `https://auth.zea.cl/oauth/introspect`)
    * `THALAMUS_CLIENT_ID` — OAuth2 client ID (required)
    * `THALAMUS_CLIENT_SECRET` — OAuth2 client secret (required)
    * `THALAMUS_CACHE_TTL` — cache TTL in seconds (default: `60`)

  ## Usage

      case ThalamusClient.introspect(token) do
        {:ok, claims} -> # token is active, claims is a map
        {:error, :inactive_token} -> # token is valid but not active
        {:error, :invalid_credentials} -> # HTTP 401 — bad client_id/secret
        {:error, :timeout} -> # request timed out after 5s
        {:error, _} -> # other errors
      end
  """

  require Logger

  @table_name :thalamus_introspect_cache
  @timeout 5_000

  @doc """
  Introspects a JWT token against the Thalamus OAuth2 server.

  Returns `{:ok, claims}` where `claims` is a map of token metadata if
  the token is active, or `{:error, reason}` on failure.

  ## Error reasons

    * `:inactive_token` — the token is valid but not active
    * `:invalid_credentials` — HTTP 401, client credentials rejected
    * `:timeout` — request exceeded 5 seconds
    * `:invalid_token` — empty or non-string token
    * `{:unexpected_status, status}` — unexpected HTTP status code
    * `{:request_failed, exception}` — transport-level failure
  """
  @spec introspect(String.t()) :: {:ok, map()} | {:error, atom() | tuple()}
  def introspect(token) when is_binary(token) and byte_size(token) > 0 do
    ensure_table!()

    case lookup(token) do
      {:ok, claims} ->
        {:ok, claims}

      :miss ->
        fetch_and_cache(token)
    end
  end

  def introspect(_), do: {:error, :invalid_token}

  # ---------------------------------------------------------------------------
  # Private — ETS management
  # ---------------------------------------------------------------------------

  defp ensure_table! do
    :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp lookup(token) do
    key = cache_key(token)

    case :ets.lookup(@table_name, key) do
      [{^key, claims, expires_at}] ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          {:ok, claims}
        else
          :ets.delete(@table_name, key)
          :miss
        end

      [] ->
        :miss
    end
  end

  defp cache(token, claims) do
    ttl = cache_ttl()
    expires_at = DateTime.add(DateTime.utc_now(), ttl, :second)
    key = cache_key(token)
    :ets.insert(@table_name, {key, claims, expires_at})
    :ok
  end

  # Hash the token for the ETS key — avoids storing raw JWTs in memory
  defp cache_key(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end

  # ---------------------------------------------------------------------------
  # Private — HTTP introspection
  # ---------------------------------------------------------------------------

  defp fetch_and_cache(token) do
    url = introspect_url()
    {client_id, client_secret} = client_credentials()

    case Req.post(url,
           auth: {:basic, "#{client_id}:#{client_secret}"},
           form: [token: token],
           receive_timeout: @timeout
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        claims = decode_body(body)

        if claims["active"] do
          cache(token, claims)
          {:ok, claims}
        else
          {:error, :inactive_token}
        end

      {:ok, %Req.Response{status: 401}} ->
        {:error, :invalid_credentials}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, %{reason: :timeout}} ->
        {:error, :timeout}

      {:error, %{reason: {:timeout, _}}} ->
        {:error, :timeout}

      {:error, error} ->
        {:error, {:request_failed, error}}
    end
  end

  defp decode_body(body) when is_map(body), do: body

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decoded
      {:error, _} -> %{"active" => false}
    end
  end

  defp decode_body(other) do
    Logger.debug("Unexpected introspect response body type: #{inspect(other)}")
    %{"active" => false}
  end

  # ---------------------------------------------------------------------------
  # Private — configuration
  # ---------------------------------------------------------------------------

  defp introspect_url do
    auth_config = Application.get_env(:cortex_community, :auth, [])
    Keyword.get(auth_config, :thalamus_introspect_url, "https://auth.zea.cl/oauth/introspect")
  end

  defp cache_ttl do
    auth_config = Application.get_env(:cortex_community, :auth, [])
    Keyword.get(auth_config, :thalamus_cache_ttl, 60)
  end

  defp client_credentials do
    auth_config = Application.get_env(:cortex_community, :auth, [])
    id = Keyword.get(auth_config, :thalamus_client_id, "")
    secret = Keyword.get(auth_config, :thalamus_client_secret, "")
    {id, secret}
  end
end
