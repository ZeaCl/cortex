defmodule CortexCommunity.Workers.QwenOAuthWorker do
  @moduledoc """
  Worker adapter for Qwen Code using OAuth credentials.

  Qwen Code uses an OpenAI-compatible API at portal.qwen.ai.
  Authentication is via OAuth Bearer token (no API key needed).

  Registered as: "qwen-oauth-local"
  Capabilities: [:chat, :tools, :vision, :fast]

  ## Usage

      iex> {:ok, creds} = QwenCredentialReader.read_credentials()
      iex> worker = QwenOAuthWorker.new(name: "qwen-oauth-local", access_token: creds.access_token)
  """

  @behaviour CortexCore.Workers.Worker

  alias CortexCore.Workers.Adapters.APIWorkerBase
  require Logger

  defstruct [:name, :access_token, :resource_url, :default_model, :timeout]

  @default_model "coder-model"
  @default_timeout 30_000

  @doc """
  Creates a new QwenOAuthWorker instance.

  Options:
    - :name - Worker identifier
    - :access_token - OAuth Bearer token
    - :resource_url - API host (default: "portal.qwen.ai")
    - :default_model - Model to use (default: "coder-model")
    - :timeout - Request timeout in ms (default: 30s)
  """
  def new(opts) do
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      access_token: Keyword.fetch!(opts, :access_token),
      resource_url: Keyword.get(opts, :resource_url, "portal.qwen.ai"),
      default_model: Keyword.get(opts, :default_model, @default_model),
      timeout: Keyword.get(opts, :timeout, @default_timeout)
    }
  end

  @impl true
  def service_type, do: :llm

  @impl true
  def health_check(worker) do
    # Qwen does not expose GET /v1/models — use a minimal chat completion instead
    payload = %{
      "model" => worker.default_model,
      "max_tokens" => 1,
      "messages" => [%{"role" => "user", "content" => "hi"}],
      "stream" => false
    }

    base_url = "https://#{worker.resource_url}"

    case Req.post(base_url <> "/v1/chat/completions",
           headers: [{"authorization", "Bearer #{worker.access_token}"}],
           json: payload,
           receive_timeout: 15_000,
           retry: false
         ) do
      {:ok, %{status: status}} when status in 200..299 -> {:ok, :available}
      # Rate limit ≠ unavailable, still healthy
      {:ok, %{status: 429}} -> {:ok, :available}
      {:ok, %{status: 401}} -> {:error, {:client_error, 401}}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      # Timeout ≠ unavailable
      {:error, %Req.TransportError{reason: :timeout}} -> {:ok, :available}
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  @impl true
  def stream_completion(worker, messages, opts) do
    APIWorkerBase.stream_completion(worker, messages, opts)
  end

  def call_with_tools(worker, messages, tools, opts) do
    opts = Keyword.put_new(opts, :model, @default_model)
    APIWorkerBase.call_with_tools(worker, messages, tools, opts)
  end

  @impl true
  def info(worker) do
    %{
      name: worker.name,
      type: :qwen_oauth,
      resource_url: worker.resource_url,
      default_model: worker.default_model,
      timeout: worker.timeout,
      status: :available
    }
  end

  @impl true
  # High priority — free tier, no API cost
  def priority(_worker), do: 8

  # ============================================
  # APIWorkerBase Callbacks
  # ============================================

  def provider_config(worker) do
    base_url = "https://#{worker.resource_url}"

    %{
      base_url: base_url,
      stream_endpoint: "/v1/chat/completions",
      tools_endpoint: "/v1/chat/completions",
      health_endpoint: base_url <> "/v1/chat/completions",
      model_param: "model",
      headers_fn: &build_headers/1,
      optional_params: %{
        "temperature" => 0.7,
        "max_tokens" => 4096,
        "stream" => true
      }
    }
  end

  def transform_messages(messages, _opts) do
    # Qwen uses OpenAI-compatible format — no transformation needed
    messages
  end

  def extract_content_from_chunk(json_data) do
    case Jason.decode(json_data) do
      {:ok, %{"choices" => [%{"delta" => delta} | _]}} ->
        content = Map.get(delta, "content")
        reasoning = Map.get(delta, "reasoning_content")

        cond do
          is_binary(content) and content != "" -> content
          is_binary(reasoning) and reasoning != "" -> reasoning
          true -> ""
        end

      _ ->
        ""
    end
  end

  def transform_tools(tools), do: %{"tools" => tools}

  def extract_tool_calls(body) do
    case body do
      %{"choices" => [%{"message" => %{"tool_calls" => calls}} | _]} ->
        Enum.flat_map(calls, &parse_tool_call/1)

      _ ->
        []
    end
  end

  # Private

  defp build_headers(worker) do
    [{"authorization", "Bearer #{worker.access_token}"}]
  end

  defp parse_tool_call(%{"function" => %{"name" => name, "arguments" => args}}) do
    case Jason.decode(args) do
      {:ok, parsed} -> [%{name: name, arguments: parsed}]
      {:error, _} -> []
    end
  end

  defp parse_tool_call(_), do: []
end
