defmodule CortexCommunityWeb.ToolsController do
  use CortexCommunityWeb, :controller
  require Logger

  @cortex_core Application.compile_env(:cortex_community, :cortex_core, CortexCore)

  plug CortexCommunityWeb.Plugs.AuthenticateApiKey

  @doc """
  Tool use / function calling endpoint.

  Accepts OpenAI-compatible tool definitions and returns structured tool_calls.
  Provider is optional — omitting it auto-routes to any worker with :tools capability.
  Specifying a provider that lacks :tools capability returns 400.
  """
  def create(conn, %{"messages" => messages, "tools" => tools} = params)
      when is_list(messages) and is_list(tools) do
    provider = params["provider"]
    tool_choice = params["tool_choice"]

    opts =
      []
      |> maybe_add_opt(:provider, provider)
      |> maybe_add_opt(:tool_choice, tool_choice)
      |> maybe_add_opt(:model, params["model"])

    Logger.info(
      "Tool use request: provider=#{provider || "auto"}, tools=#{length(tools)}, messages=#{length(messages)}"
    )

    case @cortex_core.call_with_tools(messages, tools, opts) do
      {:ok, tool_calls} ->
        json(conn, %{ok: true, tool_calls: tool_calls})

      {:error, {:worker_lacks_capability, name, :tools}} ->
        conn
        |> put_status(400)
        |> json(%{error: true, message: "Worker '#{name}' does not support tool calling"})

      {:error, {:provider_not_found, name}} ->
        conn
        |> put_status(404)
        |> json(%{error: true, message: "Worker '#{name}' not found"})

      {:error, :no_workers_available} ->
        conn
        |> put_status(503)
        |> json(%{error: true, message: "No workers available with tool calling support"})

      {:error, :rate_limited} ->
        conn
        |> put_status(429)
        |> json(%{error: true, message: "Provider rate limited, try again"})

      {:error, {status, _body}} when is_integer(status) ->
        conn
        |> put_status(502)
        |> json(%{error: true, message: "Provider error: HTTP #{status}"})

      {:error, reason} ->
        Logger.error("Tool use error: #{inspect(reason)}")

        conn
        |> put_status(500)
        |> json(%{error: true, message: "Internal server error"})
    end
  end

  def create(conn, %{"messages" => _}) do
    conn
    |> put_status(400)
    |> json(%{error: true, message: "Missing required field: tools"})
  end

  def create(conn, %{"tools" => _}) do
    conn
    |> put_status(400)
    |> json(%{error: true, message: "Missing required field: messages"})
  end

  def create(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: true, message: "Missing required fields: messages, tools"})
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)
end
