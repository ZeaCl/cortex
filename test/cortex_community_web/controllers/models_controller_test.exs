defmodule CortexCommunityWeb.ModelsControllerTest do
  use CortexCommunityWeb.ConnCase

  # Realistic fixture: based on actual CortexCore.list_workers() output
  @workers_fixture [
    %{
      name: "gemini-primary",
      type: :gemini,
      default_model: "gemini-2.5-flash",
      capabilities: []
    },
    %{
      name: "groq-primary",
      type: :groq,
      default_model: "llama-3.3-70b-versatile",
      capabilities: []
    },
    %{
      name: "tavily-primary",
      type: :search,
      default_model: nil,
      capabilities: [:search]
    }
  ]

  @health_fixture %{
    "gemini-primary" => :available,
    "groq-primary" => :available,
    "tavily-primary" => :available
  }

  # ---------------------------------------------------------------------------
  # Public access — /api/models is a public endpoint (no auth required)
  # ---------------------------------------------------------------------------

  describe "GET /api/models — public access" do
    setup do
      stub(CortexCore.Mock, :list_workers, fn -> @workers_fixture end)
      stub(CortexCore.Mock, :health_status, fn -> @health_fixture end)
      :ok
    end

    test "returns 200 without Authorization header", %{conn: conn} do
      conn = get(conn, ~p"/api/models")
      assert json = json_response(conn, 200)
      assert is_list(json["llm"])
      assert is_list(json["search"])
    end

    test "returns 200 with any authorization scheme (ignored)", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Token some-random-key")
        |> get(~p"/api/models")

      assert json_response(conn, 200)
    end
  end

  # ---------------------------------------------------------------------------
  # Success path — realistic fixture from actual live system
  # ---------------------------------------------------------------------------

  describe "GET /api/models — success" do
    setup do
      stub(CortexCommunity.Users.Mock, :authenticate_by_api_key, fn _key ->
        {:ok, user_fixture()}
      end)

      stub(CortexCore.Mock, :list_workers, fn -> @workers_fixture end)
      stub(CortexCore.Mock, :health_status, fn -> @health_fixture end)

      :ok
    end

    test "returns 200 with llm and search buckets", %{conn: conn} do
      conn =
        conn
        |> with_auth()
        |> get(~p"/api/models")

      assert json = json_response(conn, 200)
      assert is_list(json["llm"])
      assert is_list(json["search"])
      assert is_integer(json["total"])
      assert is_integer(json["available"])
    end

    test "separates LLM workers from search workers", %{conn: conn} do
      conn =
        conn
        |> with_auth()
        |> get(~p"/api/models")

      assert json = json_response(conn, 200)
      llm_ids = Enum.map(json["llm"], & &1["id"])
      search_ids = Enum.map(json["search"], & &1["id"])

      assert "gemini-primary" in llm_ids
      assert "groq-primary" in llm_ids
      assert "tavily-primary" in search_ids
    end

    test "total equals sum of llm and search workers", %{conn: conn} do
      conn =
        conn
        |> with_auth()
        |> get(~p"/api/models")

      assert json = json_response(conn, 200)
      assert json["total"] == length(json["llm"]) + length(json["search"])
    end

    test "each worker includes required fields", %{conn: conn} do
      conn =
        conn
        |> with_auth()
        |> get(~p"/api/models")

      assert json = json_response(conn, 200)

      Enum.each(json["llm"] ++ json["search"], fn worker ->
        assert Map.has_key?(worker, "id")
        assert Map.has_key?(worker, "service")
        assert Map.has_key?(worker, "status")
        assert Map.has_key?(worker, "how_to_use")
      end)
    end

    test "how_to_use includes correct endpoint per service type", %{conn: conn} do
      conn =
        conn
        |> with_auth()
        |> get(~p"/api/models")

      assert json = json_response(conn, 200)

      Enum.each(json["llm"], fn w ->
        assert w["how_to_use"]["endpoint"] == "POST /api/chat"
      end)

      Enum.each(json["search"], fn w ->
        assert w["how_to_use"]["endpoint"] == "POST /api/search"
      end)
    end

    test "available count matches workers with :available status", %{conn: conn} do
      conn =
        conn
        |> with_auth()
        |> get(~p"/api/models")

      assert json = json_response(conn, 200)
      available = Enum.count(json["llm"] ++ json["search"], &(&1["status"] == "available"))
      assert json["available"] == available
    end
  end
end
