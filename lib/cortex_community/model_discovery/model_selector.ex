defmodule CortexCommunity.ModelSelector do
  @moduledoc """
  GenServer that orchestrates model discovery, LLM-based ranking, and
  runtime model rotation.

  Lifecycle:
    1. Startup: discover available models for each active provider
    2. Use LLM (calling itself) to rank models by task type
    3. Persist results to DB (provider_models, model_rankings)
    4. Every 60s: check Pool health, rotate model if worker is unhealthy
    5. Every 24h: re-run discovery + ranking
  """

  use GenServer
  require Logger

  alias CortexCommunity.ModelDiscovery.{ModelRanking, ProviderModel}
  alias CortexCommunity.Repo
  import Ecto.Query

  @tick_interval_ms 60_000
  @daily_interval_ms 24 * 60 * 60 * 1000
  # Health check every N ticks (5 min = 5 × 60s)
  @health_check_every_ticks 5

  # Provider type → env var that holds the API key(s)
  @provider_env_keys %{
    gemini: "GEMINI_API_KEYS",
    groq: "GROQ_API_KEYS",
    openai: "OPENAI_API_KEYS",
    anthropic: "ANTHROPIC_API_KEYS",
    cohere: "COHERE_API_KEYS",
    xai: "XAI_API_KEYS"
  }

  # Worker name → provider type
  @worker_providers %{
    "gemini-primary" => :gemini,
    "gemini-pro-25-primary" => :gemini,
    "groq-primary" => :groq,
    "openai-primary" => :openai,
    "anthropic-primary" => :anthropic,
    "cohere-primary" => :cohere,
    "xai-primary" => :xai
  }

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the active model for a worker name, consulting DB.
  Returns nil if not found (supervisor falls back to env var default).
  """
  @spec get_model(String.t()) :: String.t() | nil
  def get_model(worker_name) do
    case Repo.get_by(ProviderModel, worker_name: worker_name) do
      %ProviderModel{active_model: model} when is_binary(model) and model != "" -> model
      _ -> nil
    end
  end

  @doc """
  Returns the best worker for a given task type from stored rankings.
  """
  @spec best_worker_for(String.t()) :: String.t() | nil
  def best_worker_for(task_type) do
    case Repo.get_by(ModelRanking, task_type: task_type) do
      %ModelRanking{ranked_workers: %{"workers" => [%{"worker" => w} | _]}} -> w
      _ -> nil
    end
  end

  @doc """
  Returns all rankings as a map of task_type => [workers...].
  """
  @spec get_rankings() :: map()
  def get_rankings do
    Repo.all(from(r in ModelRanking, select: {r.task_type, r.ranked_workers}))
    |> Map.new()
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    state = %{
      last_health: %{},
      discovery_done: false,
      tick_count: 0
    }

    # Schedule initial discovery (give the app time to fully start)
    Process.send_after(self(), :run_discovery, 3_000)
    {:ok, state}
  end

  @impl true
  def handle_info(:run_discovery, state) do
    new_state = do_discovery(state)

    # Schedule next daily run
    Process.send_after(self(), :run_discovery, @daily_interval_ms)

    # First boot: fire one health check right after discovery so status isn't :unknown
    unless state.discovery_done do
      Process.send_after(self(), :health_check, 500)
      Process.send_after(self(), :tick, @tick_interval_ms)
    end

    {:noreply, %{new_state | discovery_done: true}}
  end

  @impl true
  def handle_info(:health_check, state) do
    GenServer.cast(CortexCore.Workers.Pool, :check_health)
    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, state) do
    tick_count = state.tick_count + 1
    new_state = do_health_tick(state)

    # Trigger a Pool health check every @health_check_every_ticks (5 min)
    if rem(tick_count, @health_check_every_ticks) == 0 do
      GenServer.cast(CortexCore.Workers.Pool, :check_health)
    end

    Process.send_after(self(), :tick, @tick_interval_ms)
    {:noreply, %{new_state | tick_count: tick_count}}
  end

  # --- Discovery ---

  defp do_discovery(state) do
    workers = discover_all_providers()

    if Enum.empty?(workers) do
      Logger.warning("ModelSelector: no active providers found, skipping discovery")
      state
    else
      persist_provider_models(workers)
      run_llm_ranking(workers)
      configure_workers_from_db()
      state
    end
  end

  defp discover_all_providers do
    @worker_providers
    |> Enum.flat_map(fn {worker_name, provider_type} ->
      case get_first_api_key(provider_type) do
        nil -> []
        api_key -> discover_worker(worker_name, provider_type, api_key)
      end
    end)
  end

  defp get_first_api_key(provider_type) do
    env_var = Map.get(@provider_env_keys, provider_type)

    case env_var && System.get_env(env_var) do
      nil ->
        nil

      "" ->
        nil

      keys_string ->
        keys_string
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> List.first()
    end
  end

  defp discover_worker(worker_name, provider_type, api_key) do
    case CortexCore.ModelDiscovery.list_models(provider_type, api_key) do
      {:ok, []} ->
        Logger.warning("ModelSelector: #{worker_name} returned 0 models")
        []

      {:ok, models} ->
        active = List.first(models)

        Logger.info("Discovery #{worker_name}: #{length(models)} models found, active: #{active}")

        [
          %{
            worker_name: worker_name,
            provider_type: to_string(provider_type),
            models: models,
            active: active
          }
        ]

      {:error, reason} ->
        Logger.warning("ModelSelector: discovery failed for #{worker_name}: #{inspect(reason)}")
        []
    end
  end

  defp persist_provider_models(workers) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Enum.each(workers, fn %{worker_name: wn, provider_type: pt, models: models, active: active} ->
      attrs = %{
        worker_name: wn,
        provider_type: pt,
        active_model: active,
        discovered_models: models,
        current_index: 0,
        last_discovery_at: now
      }

      case Repo.get_by(ProviderModel, worker_name: wn) do
        nil ->
          %ProviderModel{}
          |> ProviderModel.changeset(attrs)
          |> Repo.insert()

        existing ->
          existing
          |> ProviderModel.changeset(attrs)
          |> Repo.update()
      end
    end)
  end

  defp configure_workers_from_db do
    # Re-register workers with models from DB
    # This updates already-registered workers' default_model
    registry = CortexCore.Workers.Registry

    Repo.all(ProviderModel)
    |> Enum.each(fn pm ->
      if pm.active_model do
        case CortexCore.Workers.Registry.update_worker(registry, pm.worker_name, %{
               default_model: pm.active_model
             }) do
          :ok -> :ok
          {:error, :not_found} -> :ok
        end
      end
    end)
  end

  # --- LLM Ranking ---

  defp run_llm_ranking(workers) do
    prompt = build_ranking_prompt(workers)

    case CortexCore.chat([%{"role" => "user", "content" => prompt}], []) do
      {:ok, stream} ->
        content =
          stream
          |> Enum.filter(&is_binary/1)
          |> Enum.join()

        parse_and_persist_rankings(content, workers)

      {:error, reason} ->
        Logger.warning("ModelSelector: LLM ranking failed: #{inspect(reason)}")
    end
  rescue
    e ->
      Logger.warning("ModelSelector: LLM ranking error: #{inspect(e)}")
  end

  defp build_ranking_prompt(workers) do
    worker_lines =
      Enum.map_join(workers, "\n", fn %{worker_name: wn, provider_type: pt, active: model} ->
        context = context_window_for(wn)
        "- #{wn} / #{model} (provider: #{pt}, context: #{context})"
      end)

    """
    You are an AI model selection expert. Based on the available workers below,
    rank them by task type. Consider context window, speed, reasoning capability,
    and cost efficiency.

    Available workers:
    #{worker_lines}

    Task types to rank:
    - chat: General conversation and Q&A
    - coding: Code generation and review
    - reasoning: Complex analysis, math, science
    - tools: Function calling and structured extraction
    - long_context: Documents > 100K tokens
    - fast: Simple tasks prioritizing speed and RPM

    Return ONLY valid JSON in this exact format (no markdown, no explanation):
    {
      "chat":         [{"worker": "...", "reason": "..."}, ...],
      "coding":       [{"worker": "...", "reason": "..."}, ...],
      "reasoning":    [{"worker": "...", "reason": "..."}, ...],
      "tools":        [{"worker": "...", "reason": "..."}, ...],
      "long_context": [{"worker": "...", "reason": "..."}, ...],
      "fast":         [{"worker": "...", "reason": "..."}, ...]
    }
    """
  end

  defp context_window_for("gemini-primary"), do: "1M tokens"
  defp context_window_for("gemini-pro-25-primary"), do: "1M tokens"
  defp context_window_for("groq-primary"), do: "128K tokens, 30RPM free"
  defp context_window_for("anthropic-primary"), do: "200K tokens"
  defp context_window_for("openai-primary"), do: "128K tokens"
  defp context_window_for("cohere-primary"), do: "128K tokens"
  defp context_window_for("xai-primary"), do: "131K tokens"
  defp context_window_for(_), do: "unknown"

  defp parse_and_persist_rankings(content, workers) do
    worker_names = Enum.map(workers, & &1.worker_name)

    with {:ok, rankings} <- Jason.decode(extract_json(content)) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      task_types = ["chat", "coding", "reasoning", "tools", "long_context", "fast"]

      Enum.each(task_types, fn task_type ->
        workers_list = Map.get(rankings, task_type, [])

        # Normalize worker field: LLM sometimes returns "worker-name / model-id".
        # Extract the known worker name if it appears anywhere in the value.
        normalized_list =
          Enum.map(workers_list, fn
            %{"worker" => w} = entry ->
              matched = Enum.find(worker_names, &String.contains?(w, &1))
              if matched, do: %{entry | "worker" => matched}, else: entry

            other ->
              other
          end)

        valid_list =
          Enum.filter(normalized_list, fn
            %{"worker" => w} -> w in worker_names
            _ -> false
          end)

        attrs = %{
          task_type: task_type,
          ranked_workers: %{"workers" => valid_list},
          generated_at: now
        }

        case Repo.get_by(ModelRanking, task_type: task_type) do
          nil ->
            %ModelRanking{}
            |> ModelRanking.changeset(attrs)
            |> Repo.insert()

          existing ->
            existing
            |> ModelRanking.changeset(attrs)
            |> Repo.update()
        end
      end)

      best =
        Enum.map_join(task_types, ", ", fn t ->
          case Map.get(rankings, t) do
            [%{"worker" => w} | _] -> "#{t}→#{w}"
            _ -> nil
          end
        end)

      Logger.info("LLM ranking generated: #{best}")
    else
      _ ->
        Logger.warning(
          "ModelSelector: could not parse LLM ranking response (raw: #{String.slice(content, 0, 200)})"
        )
    end
  end

  defp extract_json(content) do
    # Strip markdown code fences if present
    content
    |> String.replace(~r/```json\s*/i, "")
    |> String.replace(~r/```\s*/, "")
    |> String.trim()
  end

  # --- Health Tick ---

  defp do_health_tick(state) do
    current_health = CortexCore.Workers.Pool.health_status()

    # Only act on changes
    changed =
      Map.filter(current_health, fn {worker_name, health} ->
        Map.get(state.last_health, worker_name) != health
      end)

    if map_size(changed) > 0 do
      Enum.each(changed, fn {worker_name, health} ->
        handle_health_change(worker_name, health, state.last_health)
      end)
    end

    %{state | last_health: current_health}
  end

  defp handle_health_change(worker_name, :unavailable, _prev_health) do
    Logger.warning("ModelSelector: #{worker_name} unavailable, attempting model rotation")
    rotate_model(worker_name)
  end

  defp handle_health_change(worker_name, :quota_exceeded, _prev_health) do
    Logger.warning("ModelSelector: #{worker_name} quota exceeded, rotating model")
    rotate_model(worker_name)
  end

  defp handle_health_change(worker_name, :available, prev_health) do
    prev = Map.get(prev_health, worker_name)

    if prev in [:unavailable, :quota_exceeded, :rate_limited] do
      Logger.info("ModelSelector: #{worker_name} recovered (was #{prev})")
    end
  end

  defp handle_health_change(_worker_name, _health, _prev_health), do: :ok

  defp rotate_model(worker_name) do
    case Repo.get_by(ProviderModel, worker_name: worker_name) do
      nil ->
        :ok

      %ProviderModel{discovered_models: models, current_index: idx} = pm
      when is_list(models) and length(models) > 1 ->
        next_idx = rem(idx + 1, length(models))
        next_model = Enum.at(models, next_idx)

        pm
        |> ProviderModel.changeset(%{active_model: next_model, current_index: next_idx})
        |> Repo.update()

        CortexCore.Workers.Registry.update_worker(
          CortexCore.Workers.Registry,
          worker_name,
          %{default_model: next_model}
        )

        Logger.warning(
          "ModelSelector: rotated #{worker_name} to #{next_model} (index #{next_idx})"
        )

      %ProviderModel{} ->
        Logger.error("ModelSelector: #{worker_name} has no fallback models available")
    end
  end
end
