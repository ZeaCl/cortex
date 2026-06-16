defmodule CortexCommunityWeb.ModelsController do
  use CortexCommunityWeb, :controller

  alias CortexCommunity.ModelDiscovery.ModelInfo

  @cortex_core Application.compile_env(:cortex_community, :cortex_core, CortexCore)

  # list_workers() already returns info maps (result of info/1), not structs
  @search_types [:search]

  @doc """
  Lista todos los workers disponibles, su ventana de contexto y cómo usarlos.
  GET /api/models
  """
  def index(conn, _params) do
    health = @cortex_core.health_status()
    # @cortex_core.list_workers() returns info maps, not structs
    workers = @cortex_core.list_workers()

    models =
      Enum.map(workers, fn info ->
        name = info[:name] || info["name"]
        type = info[:type] || info["type"]
        model_name = info[:default_model] || info[:model] || info["model"]
        ctx = ModelInfo.context_window(model_name && to_string(model_name))
        service = if type in @search_types, do: :search, else: :llm
        caps = CortexCore.Workers.Pool.get_capabilities(name) |> Enum.map(&to_string/1)

        %{
          id: name,
          service: service,
          provider_type: type,
          model: model_name,
          status: Map.get(health, name, :unknown),
          context_window: ctx,
          capabilities: caps,
          how_to_use: usage_instructions(name, service)
        }
      end)

    llm_models = Enum.filter(models, &(&1.service == :llm))
    search_models = Enum.filter(models, &(&1.service == :search))

    json(conn, %{
      llm: llm_models,
      search: search_models,
      total: length(models),
      available: Enum.count(models, &(&1.status == :available))
    })
  end

  defp usage_instructions(worker_name, :llm) do
    %{
      endpoint: "POST /api/chat",
      note: "Use 'provider' to target this model. Without 'provider', uses best available.",
      example: %{
        provider: worker_name,
        messages: [%{role: "user", content: "your message"}]
      }
    }
  end

  defp usage_instructions(worker_name, :search) do
    %{
      endpoint: "POST /api/search",
      note:
        "Use 'provider' to target this search engine. Without 'provider', uses best available.",
      example: %{
        provider: worker_name,
        query: "your search query",
        max_results: 10
      }
    }
  end
end
