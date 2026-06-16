defmodule CortexCommunity.Auth.QwenCredentialReader do
  @moduledoc """
  Reads Qwen Code OAuth credentials from ~/.qwen/oauth_creds.json.

  The file contains:
    - access_token: Bearer token for API requests
    - refresh_token: Token to renew access_token when expired
    - resource_url: API host (e.g. "portal.qwen.ai")
    - expiry_date: Expiration in milliseconds since epoch
  """

  require Logger

  @credentials_file_path "~/.qwen/oauth_creds.json"

  @doc """
  Reads Qwen OAuth credentials from the filesystem.
  """
  def read_credentials do
    file_path = Path.expand(@credentials_file_path)

    if File.exists?(file_path) do
      try do
        file_path
        |> File.read!()
        |> Jason.decode!()
        |> parse_credentials()
      rescue
        e ->
          Logger.error("Error reading Qwen credentials: #{inspect(e)}")
          {:error, :invalid_file}
      end
    else
      {:error, :not_found}
    end
  end

  defp parse_credentials(%{
         "access_token" => access_token,
         "resource_url" => resource_url
       })
       when is_binary(access_token) and is_binary(resource_url) and access_token != "" do
    {:ok,
     %{
       access_token: access_token,
       refresh_token: nil,
       resource_url: resource_url,
       expiry_date: nil
     }}
  end

  defp parse_credentials(%{
         "access_token" => access_token,
         "resource_url" => resource_url,
         "expiry_date" => expiry_date
       })
       when is_binary(access_token) and is_binary(resource_url) and is_integer(expiry_date) do
    {:ok,
     %{
       access_token: access_token,
       refresh_token: nil,
       resource_url: resource_url,
       expiry_date: expiry_date
     }}
  end

  defp parse_credentials(%{
         "access_token" => access_token,
         "refresh_token" => refresh_token,
         "resource_url" => resource_url,
         "expiry_date" => expiry_date
       })
       when is_binary(access_token) and is_binary(resource_url) and is_integer(expiry_date) do
    {:ok,
     %{
       access_token: access_token,
       refresh_token: refresh_token,
       resource_url: resource_url,
       expiry_date: expiry_date
     }}
  end

  defp parse_credentials(_), do: {:error, :invalid_format}

  @doc """
  Checks if Qwen credentials are still valid (not expired).
  Returns true if no expiry_date is set (assume valid).
  """
  def valid?(%{expiry_date: nil}), do: true

  def valid?(%{expiry_date: expiry_date}) when is_integer(expiry_date) do
    System.system_time(:millisecond) < expiry_date
  end

  def valid?(_), do: false

  @doc """
  Returns the path where Qwen CLI stores credentials.
  """
  def credentials_path, do: Path.expand(@credentials_file_path)
end
