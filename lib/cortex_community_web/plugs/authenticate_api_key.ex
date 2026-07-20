defmodule CortexCommunityWeb.Plugs.AuthenticateApiKey do
  @moduledoc """
  Plug for authenticating requests using Cortex API keys or Thalamus JWT tokens.

  The authentication mode is controlled by the `AUTH_MODE` environment variable:

    * `local` — only `ctx_` API keys (current behavior, dev)
    * `thalamus` — only JWT tokens validated via Thalamus `/oauth/introspect`
    * `hybrid` — both (default)

  Expects an `Authorization` header:

    * `Bearer ctx_...` — local API key
    * `Bearer ctx_...` (without Bearer prefix) — also accepted
    * `Bearer <JWT>` — Thalamus access token (thalamus/hybrid modes)

  On successful authentication, assigns to conn:

    * `conn.assigns.cortex_user` — `CortexUser.t()` or `nil` (thalamus)
    * `conn.assigns.auth_source` — `:local` | `:thalamus`
    * `conn.assigns.auth_claims` — JWT claims map or `nil` (local)

  On authentication failure, returns 401 Unauthorized.

  ## Usage

      plug CortexCommunityWeb.Plugs.AuthenticateApiKey
  """

  import Plug.Conn
  require Logger

  alias CortexCommunity.Auth.AuthManager
  @users Application.compile_env(:cortex_community, :users_module, CortexCommunity.Users)

  def init(opts), do: opts

  def call(conn, _opts) do
    auth_mode = get_auth_mode()

    case extract_token(conn) do
      {:ok, token} ->
        case AuthManager.authenticate(token, auth_mode) do
          {:ok, auth_info} ->
            conn
            |> assign(:cortex_user, auth_info.user)
            |> assign(:auth_source, auth_info.source)
            |> assign(:auth_claims, auth_info.claims)

          {:error, reason} ->
            handle_error(conn, reason)
        end

      {:error, reason} ->
        handle_error(conn, reason)
    end
  end

  # ---------------------------------------------------------------------------
  # Token extraction
  # ---------------------------------------------------------------------------

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      [] ->
        {:error, :missing_authorization}

      [auth_header | _] ->
        parse_auth_header(auth_header)
    end
  end

  defp parse_auth_header("Bearer " <> token), do: {:ok, String.trim(token)}
  defp parse_auth_header("bearer " <> token), do: {:ok, String.trim(token)}
  defp parse_auth_header("ctx_" <> _ = token), do: {:ok, String.trim(token)}
  defp parse_auth_header(_), do: {:error, :invalid_authorization_format}

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------

  defp handle_error(conn, reason) do
    Logger.warning("Authentication failed: #{inspect(reason)}")

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{
      error: "unauthorized",
      message: format_error_message(reason)
    }))
    |> halt()
  end

  defp format_error_message(:missing_authorization),
    do: "Missing Authorization header. Use: Bearer ctx_... or Bearer <JWT>"

  defp format_error_message(:invalid_authorization_format),
    do: "Invalid authorization header format. Use: Bearer ctx_... or Bearer <JWT>"

  defp format_error_message(:invalid_api_key), do: "Invalid API key"
  defp format_error_message(:expired_api_key), do: "API key has expired"
  defp format_error_message(:inactive_token), do: "Token is not active"
  defp format_error_message(:invalid_credentials), do: "Invalid client credentials"
  defp format_error_message(:timeout), do: "Authentication service timeout"
  defp format_error_message(:local_keys_not_allowed_in_thalamus_mode),
    do: "Local API keys are not allowed in thalamus auth mode"
  defp format_error_message(_), do: "Authentication failed"

  # ---------------------------------------------------------------------------
  # Configuration
  # ---------------------------------------------------------------------------

  defp get_auth_mode do
    auth_config = Application.get_env(:cortex_community, :auth, [])
    Keyword.get(auth_config, :mode, :hybrid)
  end
end
