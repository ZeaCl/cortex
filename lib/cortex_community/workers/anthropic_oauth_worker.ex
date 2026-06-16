defmodule CortexCommunity.Workers.AnthropicOAuthWorker do
  @moduledoc """
  Worker adapter for Claude using OAuth credentials (Claude Pro Max).

  Uses Finch (via APIWorkerBase) for streaming — same as all other workers —
  so HTTPoison async messages never land on the Pool GenServer.

  Registered as: "anthropic-oauth-local"
  Capabilities: [:chat, :tools, :reasoning]
  """

  @behaviour CortexCore.Workers.Worker

  alias CortexCommunity.Auth.ClaudeCliReader
  alias CortexCore.Workers.Adapters.APIWorkerBase
  require Logger

  defstruct [:name, :credentials, :default_model, :timeout]

  @default_model "claude-sonnet-4-5-20250929"
  @default_timeout 60_000
  @api_base "https://api.anthropic.com"
  @stream_endpoint "/v1/messages?beta=true"
  @anthropic_version "2023-06-01"

  def new(opts) do
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      credentials: Keyword.fetch!(opts, :credentials),
      default_model: Keyword.get(opts, :default_model, @default_model),
      timeout: Keyword.get(opts, :timeout, @default_timeout)
    }
  end

  @impl true
  def service_type, do: :llm

  @impl true
  def health_check(worker) do
    unless ClaudeCliReader.valid?(worker.credentials) do
      {:error, :expired_credentials}
    else
      payload = %{
        "model" => worker.default_model,
        "max_tokens" => 1,
        "messages" => [%{"role" => "user", "content" => "Hi"}]
      }

      case Req.post(@api_base <> @stream_endpoint,
             headers: build_headers(worker),
             json: payload,
             receive_timeout: 5_000,
             retry: false
           ) do
        {:ok, %{status: status}} when status in 200..299 -> {:ok, :available}
        {:ok, %{status: 429}} -> {:error, :rate_limited}
        {:ok, %{status: 401}} -> {:error, :expired_credentials}
        {:ok, %{status: status}} -> {:error, {:http_error, status}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def stream_completion(worker, messages, opts) do
    # Uses Finch via APIWorkerBase — no HTTPoison async messages to the Pool
    APIWorkerBase.stream_completion(worker, messages, opts)
  end

  @doc """
  Tool calling via Anthropic Messages API with OAuth headers.
  Converts OpenAI-format tools to Anthropic format.
  """
  def call_with_tools(worker, messages, tools, opts) do
    model = Keyword.get(opts, :model, worker.default_model)
    {system_content, user_messages} = extract_system(messages)

    payload =
      %{
        "model" => model,
        "max_tokens" => 4_096,
        "messages" => user_messages,
        "tools" => convert_tools_to_anthropic(tools),
        "stream" => false
      }
      |> maybe_add_system(system_content)
      |> maybe_add_tool_choice(opts)

    case Req.post(@api_base <> @stream_endpoint,
           headers: build_headers(worker),
           json: payload,
           receive_timeout: worker.timeout,
           retry: false
         ) do
      {:ok, %{status: 200, body: body}} -> {:ok, extract_tool_calls(body)}
      {:ok, %{status: 429}} -> {:error, :rate_limited}
      {:ok, %{status: 401}} -> {:error, :expired_credentials}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def info(worker) do
    %{
      name: worker.name,
      type: :anthropic_oauth,
      default_model: worker.default_model,
      timeout: worker.timeout,
      status: :available
    }
  end

  @impl true
  # Highest LLM priority — free Pro Max tier
  def priority(_worker), do: 5

  # ============================================
  # APIWorkerBase Callbacks (for Finch streaming)
  # ============================================

  def provider_config(_worker) do
    %{
      base_url: @api_base,
      stream_endpoint: @stream_endpoint,
      tools_endpoint: @stream_endpoint,
      health_endpoint: @api_base,
      model_param: "model",
      headers_fn: &build_headers/1,
      optional_params: %{
        "max_tokens" => 4_096,
        "stream" => true
      }
    }
  end

  def transform_messages(messages, _opts) do
    {sys, rest} =
      Enum.split_with(messages, fn m ->
        role = m["role"] || m[:role]
        role == "system"
      end)

    base = %{
      "messages" =>
        Enum.map(rest, fn m ->
          %{
            "role" => to_string(m["role"] || m[:role] || "user"),
            "content" => m["content"] || m[:content]
          }
        end)
    }

    case sys do
      [h | _] -> Map.put(base, "system", h["content"] || h[:content])
      [] -> base
    end
  end

  def extract_content_from_chunk(json_data) do
    case Jason.decode(json_data) do
      {:ok, %{"type" => "content_block_delta", "delta" => %{"text" => text}}} -> text
      {:ok, %{"content" => [%{"type" => "text", "text" => text} | _]}} -> text
      {:ok, %{"type" => _}} -> ""
      _ -> ""
    end
  end

  # Private helpers

  defp build_headers(worker) do
    [
      {"authorization", "Bearer #{worker.credentials.access_token}"},
      {"anthropic-version", @anthropic_version},
      {"anthropic-beta", "oauth-2025-04-20"},
      {"anthropic-dangerous-direct-browser-access", "true"}
    ]
  end

  defp extract_system(messages) do
    {sys, rest} =
      Enum.split_with(messages, fn m ->
        role = m["role"] || m[:role]
        role == "system"
      end)

    system =
      case sys do
        [h | _] -> h["content"] || h[:content]
        [] -> nil
      end

    formatted =
      Enum.map(rest, fn m ->
        %{
          "role" => to_string(m["role"] || m[:role] || "user"),
          "content" => m["content"] || m[:content]
        }
      end)

    {system, formatted}
  end

  defp maybe_add_system(payload, nil), do: payload
  defp maybe_add_system(payload, system), do: Map.put(payload, "system", system)

  defp maybe_add_tool_choice(payload, opts) do
    case Keyword.get(opts, :tool_choice) do
      nil -> payload
      tc -> Map.put(payload, "tool_choice", tc)
    end
  end

  defp convert_tools_to_anthropic(tools) do
    Enum.map(tools, fn
      %{"function" => %{"name" => name} = func} ->
        %{
          "name" => name,
          "description" => Map.get(func, "description", ""),
          "input_schema" =>
            Map.get(func, "parameters", %{"type" => "object", "properties" => %{}})
        }

      tool ->
        tool
    end)
  end

  defp extract_tool_calls(%{"content" => content}) when is_list(content) do
    content
    |> Enum.filter(&(&1["type"] == "tool_use"))
    |> Enum.map(fn block -> %{name: block["name"], arguments: block["input"]} end)
  end

  defp extract_tool_calls(_), do: []
end
