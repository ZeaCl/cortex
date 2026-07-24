# lib/cortex_community_web/controllers/health_controller.ex
defmodule CortexCommunityWeb.HealthController do
  use CortexCommunityWeb, :controller

  alias CortexCommunity.ModelDiscovery.{ModelInfo, ProviderModel}
  alias CortexCommunity.Repo

  @cortex_core Application.compile_env(:cortex_community, :cortex_core, CortexCore)

  @doc """
  Basic health check endpoint
  """
  def index(conn, _params) do
    health = @cortex_core.health_status()
    available_workers = Enum.count(health, fn {_, status} -> status == :available end)
    total_workers = map_size(health)

    status = if available_workers > 0, do: "healthy", else: "degraded"

    json(conn, %{
      status: status,
      available_workers: available_workers,
      total_workers: total_workers,
      timestamp: DateTime.utc_now()
    })
  end

  @doc """
  Detailed health status of all workers
  """
  def workers(conn, _params) do
    health = @cortex_core.health_status()
    workers = @cortex_core.list_workers()

    worker_details =
      Enum.map(workers, fn worker ->
        %{
          name: worker.name,
          type: worker.type,
          priority: Map.get(worker, :priority, 100),
          status: Map.get(health, worker.name, :unknown),
          api_keys_count: Map.get(worker, :api_keys_count, 0)
        }
      end)

    json(conn, %{
      workers: worker_details,
      summary: %{
        total: length(worker_details),
        available: Enum.count(worker_details, &(&1.status == :available)),
        unavailable: Enum.count(worker_details, &(&1.status == :unavailable)),
        rate_limited: Enum.count(worker_details, &(&1.status == :rate_limited))
      }
    })
  end

  @doc """
  Full system status: workers, active models, fallback pool, task recommendations.
  Designed for services to query before using Cortex.
  """
  def detailed(conn, _params) do
    health = @cortex_core.health_status()
    workers = @cortex_core.list_workers()
    stats = CortexCommunity.StatsCollector.get_stats()

    provider_models =
      try do
        Repo.all(ProviderModel)
      rescue
        _ -> []
      end

    rankings =
      try do
        CortexCommunity.ModelSelector.get_rankings()
      rescue
        _ -> %{}
      end

    pm_by_name = Map.new(provider_models, &{&1.worker_name, &1})

    llm_workers =
      workers
      |> Enum.filter(
        &(&1.type in [:gemini, :anthropic, :openai, :groq, :cohere, :xai, :ollama, :qwen_oauth])
      )
      |> Enum.map(&build_worker_detail(&1, health, pm_by_name))

    search_workers =
      workers
      |> Enum.filter(&(&1.type == :search))
      |> Enum.map(&build_worker_detail(&1, health, pm_by_name))

    available_llm = Enum.count(llm_workers, &(&1.status == "available"))
    available_search = Enum.count(search_workers, &(&1.status == "available"))

    recommendations = build_recommendations(rankings, health)

    json(conn, %{
      status: overall_status(available_llm),
      gateway: %{
        version: Application.spec(:cortex_community, :vsn) |> to_string(),
        core_version: Application.spec(:cortex_core, :vsn) |> to_string(),
        uptime: format_uptime(stats[:uptime_seconds] || 0),
        memory_mb: div(:erlang.memory(:total), 1024 * 1024)
      },
      llm: %{
        available: available_llm,
        total: length(llm_workers),
        workers: llm_workers
      },
      search: %{
        available: available_search,
        total: length(search_workers),
        workers: search_workers
      },
      recommendations: recommendations,
      timestamp: DateTime.utc_now()
    })
  end

  # --- Private ---

  defp build_worker_detail(worker, health, pm_by_name) do
    status = Map.get(health, worker.name, :unknown)
    pm = Map.get(pm_by_name, worker.name)

    model = Map.get(worker, :model) || Map.get(worker, :default_model)
    caps = CortexCore.Workers.Pool.get_capabilities(worker.name) |> Enum.map(&to_string/1)

    base = %{
      name: worker.name,
      status: to_string(status),
      model: model,
      context_window: ModelInfo.context_window(model && to_string(model)),
      capabilities: caps
    }

    if pm do
      Map.merge(base, %{
        fallback_models: length(pm.discovered_models),
        last_discovery: pm.last_discovery_at
      })
    else
      base
    end
  end

  defp build_recommendations(rankings, health) do
    task_types = ["chat", "coding", "reasoning", "tools", "long_context", "fast"]

    Map.new(task_types, fn task ->
      workers_list =
        case Map.get(rankings, task) do
          %{"workers" => list} -> list
          _ -> []
        end

      # Find best available worker for this task
      best =
        Enum.find(workers_list, fn %{"worker" => w} ->
          Map.get(health, w, :unknown) not in [:unavailable, :quota_exceeded]
        end)

      {task,
       case best do
         %{"worker" => w, "reason" => r} -> %{worker: w, reason: r}
         _ -> nil
       end}
    end)
  end

  defp overall_status(0), do: "degraded"
  defp overall_status(_), do: "ready"

  defp format_uptime(seconds) do
    days = div(seconds, 86_400)
    hours = div(rem(seconds, 86_400), 3600)
    minutes = div(rem(seconds, 3600), 60)

    [
      if(days > 0, do: "#{days}d"),
      if(hours > 0, do: "#{hours}h"),
      if(minutes > 0, do: "#{minutes}m")
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> "< 1m"
      parts -> Enum.join(parts, " ")
    end
  end
end

# lib/cortex_community_web/controllers/stats_controller.ex
defmodule CortexCommunityWeb.StatsController do
  use CortexCommunityWeb, :controller

  alias CortexCommunity.StatsCollector

  @doc """
  Get general statistics
  """
  def index(conn, _params) do
    stats = StatsCollector.get_stats()
    json(conn, build_stats_response(stats))
  end

  defp build_stats_response(stats) do
    %{
      requests: build_requests_stats(stats),
      performance: build_performance_stats(stats),
      uptime: build_uptime_stats(stats),
      timestamp: DateTime.utc_now()
    }
  end

  defp build_requests_stats(stats) do
    %{
      total: stats[:requests_total] || 0,
      completed: stats[:requests_completed] || 0,
      failed: stats[:requests_failed] || 0,
      no_workers: stats[:requests_no_workers] || 0,
      active: stats[:requests_active] || 0
    }
  end

  defp build_performance_stats(stats) do
    %{
      average_duration_ms: stats[:average_duration] || 0,
      total_tokens: stats[:total_tokens] || 0,
      tokens_per_second: stats[:tokens_per_second] || 0
    }
  end

  defp build_uptime_stats(stats) do
    %{
      seconds: stats[:uptime_seconds] || 0,
      formatted: format_uptime(stats[:uptime_seconds] || 0)
    }
  end

  @doc """
  Get per-provider statistics
  """
  def providers(conn, _params) do
    stats = StatsCollector.get_provider_stats()

    provider_details =
      Enum.map(stats, fn {provider, data} ->
        %{
          provider: provider,
          requests_total: data[:requests_total] || 0,
          requests_completed: data[:requests_completed] || 0,
          requests_failed: data[:requests_failed] || 0,
          total_tokens: data[:total_tokens] || 0,
          average_duration_ms: data[:average_duration] || 0,
          error_rate: calculate_error_rate(data),
          last_used: data[:last_used]
        }
      end)

    json(conn, %{
      providers: provider_details,
      summary: %{
        total_providers: length(provider_details),
        active_providers: Enum.count(provider_details, &(&1.requests_total > 0))
      }
    })
  end

  # Private functions

  defp format_uptime(seconds) do
    days = div(seconds, 86_400)
    hours = div(rem(seconds, 86_400), 3600)
    minutes = div(rem(seconds, 3600), 60)

    parts = []
    parts = if days > 0, do: ["#{days}d" | parts], else: parts
    parts = if hours > 0, do: ["#{hours}h" | parts], else: parts
    parts = if minutes > 0, do: ["#{minutes}m" | parts], else: parts

    if parts == [], do: "< 1m", else: Enum.join(Enum.reverse(parts), " ")
  end

  defp calculate_error_rate(%{requests_total: 0}), do: 0.0

  defp calculate_error_rate(%{requests_total: total, requests_failed: failed}) do
    Float.round(failed / total * 100, 2)
  end

  defp calculate_error_rate(_), do: 0.0
end
