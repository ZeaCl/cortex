defmodule CortexCommunityWeb.HealthControllerTest do
  use CortexCommunityWeb.ConnCase

  # Realistic worker fixture based on actual CortexCore worker info maps
  @workers_fixture [
    %{name: "gemini-primary", type: :gemini, default_model: "gemini-2.5-flash", capabilities: []},
    %{
      name: "groq-primary",
      type: :groq,
      default_model: "llama-3.3-70b-versatile",
      capabilities: []
    }
  ]

  @health_fixture %{"gemini-primary" => :available, "groq-primary" => :available}

  # All health endpoints use @cortex_core mock (public, no auth required)
  setup do
    stub(CortexCore.Mock, :health_status, fn -> @health_fixture end)
    stub(CortexCore.Mock, :list_workers, fn -> @workers_fixture end)
    :ok
  end

  # ---------------------------------------------------------------------------
  # GET /api/health — basic health check (public, no auth)
  # ---------------------------------------------------------------------------

  describe "GET /api/health" do
    test "returns status without authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/health")
      assert json = json_response(conn, 200)
      assert Map.has_key?(json, "status")
      assert json["status"] in ["healthy", "degraded"]
      assert Map.has_key?(json, "timestamp")
      assert Map.has_key?(json, "available_workers")
      assert Map.has_key?(json, "total_workers")
    end

    test "status is healthy when workers are available", %{conn: conn} do
      conn = get(conn, ~p"/api/health")
      assert json = json_response(conn, 200)
      assert json["status"] == "healthy"
      assert json["available_workers"] == 2
    end
  end

  # ---------------------------------------------------------------------------
  # GET /api/health/workers — worker list (public, no auth)
  # ---------------------------------------------------------------------------

  describe "GET /api/health/workers" do
    test "returns worker list without authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/health/workers")
      assert json = json_response(conn, 200)
      assert Map.has_key?(json, "workers")
      assert Map.has_key?(json, "summary")
      assert is_list(json["workers"])
    end

    test "summary includes required keys", %{conn: conn} do
      conn = get(conn, ~p"/api/health/workers")
      assert json = json_response(conn, 200)
      summary = json["summary"]
      assert Map.has_key?(summary, "total")
      assert Map.has_key?(summary, "available")
    end

    test "each worker entry includes name, type, and status", %{conn: conn} do
      conn = get(conn, ~p"/api/health/workers")
      assert json = json_response(conn, 200)

      # With the fixture workers, the lambda inside Enum.map IS exercised
      assert length(json["workers"]) == 2

      Enum.each(json["workers"], fn worker ->
        assert Map.has_key?(worker, "name")
        assert Map.has_key?(worker, "type")
        assert Map.has_key?(worker, "status")
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # GET /api/health/detailed — full health + stats (public, no auth)
  # ---------------------------------------------------------------------------

  describe "GET /api/health/detailed" do
    test "returns health and stats without authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/health/detailed")
      assert json = json_response(conn, 200)
      assert Map.has_key?(json, "status")
      assert Map.has_key?(json, "gateway")
      assert Map.has_key?(json, "llm")
      assert Map.has_key?(json, "search")
      assert Map.has_key?(json, "recommendations")
    end

    test "gateway section includes version and memory info", %{conn: conn} do
      conn = get(conn, ~p"/api/health/detailed")
      assert json = json_response(conn, 200)
      gateway = json["gateway"]
      assert Map.has_key?(gateway, "version")
      assert Map.has_key?(gateway, "memory_mb")
      assert Map.has_key?(gateway, "uptime")
    end
  end

  # ---------------------------------------------------------------------------
  # GET /api/stats — request statistics (public, no auth)
  # ---------------------------------------------------------------------------

  describe "GET /api/stats" do
    test "returns stats without authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/stats")
      assert json = json_response(conn, 200)
      assert Map.has_key?(json, "requests")
      assert Map.has_key?(json, "performance")
      assert Map.has_key?(json, "uptime")
      assert Map.has_key?(json, "timestamp")
    end

    test "requests section has required fields", %{conn: conn} do
      conn = get(conn, ~p"/api/stats")
      assert json = json_response(conn, 200)
      requests = json["requests"]
      assert Map.has_key?(requests, "total")
      assert Map.has_key?(requests, "completed")
      assert Map.has_key?(requests, "failed")
      assert Map.has_key?(requests, "active")
    end

    test "performance section has required fields", %{conn: conn} do
      conn = get(conn, ~p"/api/stats")
      assert json = json_response(conn, 200)
      perf = json["performance"]
      assert Map.has_key?(perf, "average_duration_ms")
      assert Map.has_key?(perf, "total_tokens")
    end

    test "uptime section has seconds and formatted fields", %{conn: conn} do
      conn = get(conn, ~p"/api/stats")
      assert json = json_response(conn, 200)
      uptime = json["uptime"]
      assert Map.has_key?(uptime, "seconds")
      assert Map.has_key?(uptime, "formatted")
      assert is_binary(uptime["formatted"])
    end
  end

  # ---------------------------------------------------------------------------
  # GET /api/stats/providers — per-provider statistics (public, no auth)
  # ---------------------------------------------------------------------------

  describe "GET /api/stats/providers" do
    test "returns provider stats without authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/stats/providers")
      assert json = json_response(conn, 200)
      assert Map.has_key?(json, "providers")
      assert Map.has_key?(json, "summary")
      assert is_list(json["providers"])
    end

    test "summary includes total and active provider counts", %{conn: conn} do
      conn = get(conn, ~p"/api/stats/providers")
      assert json = json_response(conn, 200)
      summary = json["summary"]
      assert Map.has_key?(summary, "total_providers")
      assert Map.has_key?(summary, "active_providers")
    end

    test "includes per-provider data when providers have been tracked", %{conn: conn} do
      # Pre-populate provider stats so the Enum.map body is exercised
      CortexCommunity.StatsCollector.track_provider("gemini-primary", :request, %{})

      CortexCommunity.StatsCollector.track_provider("gemini-primary", :completed, %{
        duration: 250,
        tokens: 40
      })

      conn = get(conn, ~p"/api/stats/providers")
      assert json = json_response(conn, 200)
      assert is_list(json["providers"])

      # At least one provider entry should be present
      assert json["summary"]["total_providers"] >= 1
    end
  end
end
