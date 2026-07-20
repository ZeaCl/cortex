defmodule CortexCommunity.Auth.AuthManager do
  @moduledoc """
  Authentication dispatcher that supports three auth modes:

    * `:local` — only `ctx_` API keys (current behavior, dev)
    * `:thalamus` — only JWT tokens validated via Thalamus introspect
    * `:hybrid` — both (default, for gradual migration)

  ## Auth info map

  On success, returns `{:ok, auth_info}` where `auth_info` is:

      %{
        user: CortexUser.t() | nil,
        source: :local | :thalamus,
        claims: map() | nil  # JWT claims (domain_roles, scopes, client_id...)
      }
  """

  alias CortexCommunity.Auth.ThalamusClient

  @doc """
  Authenticates a token based on the configured auth mode.

  Returns `{:ok, auth_info}` or `{:error, reason}`.
  """
  @spec authenticate(String.t(), atom()) ::
          {:ok, map()} | {:error, atom() | tuple()}
  def authenticate(token, mode \\ get_mode())

  # ---------------------------------------------------------------------------
  # Mode: local — exactly current behavior, delegate to Users.authenticate_by_api_key
  # ---------------------------------------------------------------------------

  def authenticate(token, :local) do
    case users_module().authenticate_by_api_key(token) do
      {:ok, user} ->
        {:ok, %{user: user, source: :local, claims: nil}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Mode: hybrid — ctx_ keys go to local, everything else goes to Thalamus
  # ---------------------------------------------------------------------------

  def authenticate("ctx_" <> _ = token, :hybrid) do
    require Logger
    Logger.warning("Using deprecated ctx_ API key. Migrate to Thalamus OAuth2 tokens.")

    authenticate(token, :local)
  end

  def authenticate(token, :hybrid) do
    case ThalamusClient.introspect(token) do
      {:ok, claims} ->
        {:ok, %{user: nil, source: :thalamus, claims: claims}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Mode: thalamus — only JWT via Thalamus, reject local keys
  # ---------------------------------------------------------------------------

  def authenticate("ctx_" <> _, :thalamus) do
    {:error, :local_keys_not_allowed_in_thalamus_mode}
  end

  def authenticate(token, :thalamus) do
    case ThalamusClient.introspect(token) do
      {:ok, claims} ->
        {:ok, %{user: nil, source: :thalamus, claims: claims}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — configuration
  # ---------------------------------------------------------------------------

  defp get_mode do
    auth_config = Application.get_env(:cortex_community, :auth, [])
    Keyword.get(auth_config, :mode, :hybrid)
  end

  defp users_module do
    Application.get_env(:cortex_community, :users_module, CortexCommunity.Users)
  end
end
