defmodule CortexCore.Workers.Adapters.MLXWorker do
  @moduledoc """
  Worker adapter para zea/models — servidor MLX local con API OpenAI-compatible.

  Características:
  - Modelos: mlx-vision (Qwen2.5-VL-3B-Instruct-4bit), mlx-text (Qwen2.5-3B-Instruct-4bit)
  - API OpenAI-compatible en /v1/chat/completions
  - Health check en /health
  - Sin API keys (servidor local en Apple Silicon)
  - Optimizado para desarrollo local en macOS con chips M-series
  """

  @behaviour CortexCore.Workers.Worker

  alias CortexCore.Workers.Adapters.APIWorkerBase

  # ============================================
  # Worker Behaviour Implementation
  # ============================================

  @impl true
  def service_type, do: :llm

  defstruct [:name, :base_url, :default_model, :timeout]

  @default_timeout 60_000
  @default_model "mlx-text"
  @base_url "http://localhost:8000"
  @stream_endpoint "/v1/chat/completions"

  @doc """
  Crea una nueva instancia de MLXWorker.

  Options:
    - :name - Nombre identificador del worker
    - :base_url - URL base del servidor zea/models (default: "http://localhost:8000")
    - :default_model - Modelo por defecto a usar (default: "mlx-text")
    - :timeout - Timeout para peticiones en ms (default: 60_000)
  """
  def new(opts) do
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      base_url: Keyword.get(opts, :base_url, @base_url),
      default_model: Keyword.get(opts, :default_model, @default_model),
      timeout: Keyword.get(opts, :timeout, @default_timeout)
    }
  end

  @impl true
  def health_check(worker) do
    APIWorkerBase.health_check(worker)
  end

  @impl true
  def stream_completion(worker, messages, opts) do
    APIWorkerBase.stream_completion(worker, messages, opts)
  end

  @impl true
  def info(worker) do
    %{
      name: worker.name,
      type: :mlx,
      base_url: worker.base_url,
      default_model: worker.default_model,
      available_models: ["mlx-vision", "mlx-text"],
      timeout: worker.timeout,
      status: :available
    }
  end

  @impl true
  # Alta prioridad: después de workers locales, antes de APIs cloud.
  # Ideal para desarrollo: si MLX está disponible se usa preferentemente.
  def priority(_worker), do: 10

  # ============================================
  # Callbacks para APIWorkerBase
  # ============================================

  @doc false
  def provider_config(worker) do
    %{
      base_url: worker.base_url,
      stream_endpoint: @stream_endpoint,
      health_endpoint: worker.base_url <> "/health",
      model_param: "model",
      headers_fn: &build_headers/1,
      optional_params: %{
        "stream" => true
      }
    }
  end

  @doc false
  def transform_messages(messages, _opts) do
    # zea/models usa formato OpenAI estándar, no necesita transformación
    %{
      "messages" => messages
    }
  end

  @doc false
  def extract_content_from_chunk(json_data) do
    case Jason.decode(json_data) do
      {:ok, %{"choices" => [%{"delta" => %{"content" => content}} | _]}}
      when is_binary(content) ->
        content

      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}}
      when is_binary(content) ->
        content

      {:ok, %{"choices" => [%{"delta" => %{"reasoning" => _reasoning, "content" => content}} | _]}}
      when is_binary(content) ->
        content

      _ ->
        ""
    end
  end

  # ============================================
  # Funciones privadas
  # ============================================

  defp build_headers(_worker) do
    # Sin API keys — servidor local sin autenticación
    []
  end
end
