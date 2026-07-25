defmodule CortexCore.Workers.Adapters.DeepSeekWorker do
  @moduledoc """
  Worker adapter for DeepSeek models.

  DeepSeek uses an OpenAI-compatible API, so this worker is nearly identical
  to OpenAIWorker with different defaults.

  ## Características
  - Modelos: deepseek-chat, deepseek-reasoner
  - Context: 128K tokens
  - API compatible con OpenAI
  - Base URL: https://api.deepseek.com
  """

  @behaviour CortexCore.Workers.Worker

  alias CortexCore.Workers.Adapters.APIWorkerBase

  defstruct [
    :name,
    :api_keys,
    :current_key_index,
    :default_model,
    :timeout,
    :last_rotation,
    :base_url
  ]

  @default_timeout 60_000
  @default_model "deepseek-chat"
  @base_url "https://api.deepseek.com"
  @stream_endpoint "/v1/chat/completions"

  @doc """
  Crea una nueva instancia de DeepSeekWorker.
  """
  def new(opts) do
    api_keys =
      case Keyword.get(opts, :api_keys) do
        keys when is_list(keys) and keys != [] -> keys
        single_key when is_binary(single_key) -> [single_key]
        _ -> raise ArgumentError, "api_keys debe ser una lista no vacía o string"
      end

    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      api_keys: api_keys,
      current_key_index: 0,
      default_model: Keyword.get(opts, :default_model, @default_model),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      last_rotation: nil,
      base_url: Keyword.get(opts, :base_url, @base_url)
    }
  end

  @impl true
  def service_type, do: :deepseek

  @impl true
  def health_check(worker, http_client \\ Req) do
    APIWorkerBase.health_check(worker, http_client)
  end

  @impl true
  def stream_completion(worker, messages, opts) do
    APIWorkerBase.stream_completion(worker, messages, opts)
  end

  @impl true
  def info(worker) do
    base_info = APIWorkerBase.worker_info(worker, :deepseek)

    Map.merge(base_info, %{
      base_url: worker.base_url,
      default_model: worker.default_model,
      available_models: [
        "deepseek-chat",
        "deepseek-reasoner"
      ]
    })
  end

  @impl true
  def priority(_worker), do: 4

  # Callbacks para APIWorkerBase

  def provider_config(worker) do
    %{
      base_url: worker.base_url,
      stream_endpoint: @stream_endpoint,
      health_endpoint: worker.base_url <> "/v1/models",
      model_param: "model",
      headers_fn: &build_headers/1,
      optional_params: %{
        "stream" => true,
        "temperature" => 0.7
      }
    }
  end

  def transform_messages(messages, _opts) do
    %{"messages" => messages}
  end

  def extract_content_from_chunk(json_data) do
    case Jason.decode(json_data) do
      # Specific: deepseek-reasoner returns reasoning_content + content in delta
      {:ok, %{"choices" => [%{"delta" => %{"reasoning_content" => _, "content" => content}} | _]}} ->
        content

      # Generic: standard delta with content (deepseek-chat, OpenAI-compatible)
      {:ok, %{"choices" => [%{"delta" => %{"content" => content}} | _]}} ->
        content

      # Non-streaming: full message in response
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        content

      _ ->
        ""
    end
  end

  @doc """
  Rota al siguiente API key disponible.
  """
  def rotate_api_key(worker) do
    new_index = rem(worker.current_key_index + 1, length(worker.api_keys))

    %{worker | current_key_index: new_index, last_rotation: DateTime.utc_now()}
  end

  @doc """
  Obtiene el API key actual.
  """
  def current_api_key(worker) do
    Enum.at(worker.api_keys, worker.current_key_index)
  end

  # Funciones privadas

  defp build_headers(worker) do
    api_key = current_api_key(worker)
    [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]
  end
end
