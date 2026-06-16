defmodule CortexCommunityWeb.ToolsControllerTest do
  use CortexCommunityWeb.ConnCase

  @valid_messages [%{"role" => "user", "content" => "Analiza este módulo: UserAuth"}]
  @valid_tools [
    %{
      "type" => "function",
      "function" => %{
        "name" => "extract_spec",
        "description" => "Extrae datos estructurados del spec",
        "parameters" => %{
          "type" => "object",
          "properties" => %{
            "name" => %{"type" => "string"},
            "priority" => %{"type" => "string", "enum" => ["high", "medium", "low"]}
          },
          "required" => ["name", "priority"]
        }
      }
    }
  ]

  # Realistic fixture based on actual Gemini tool call response
  @tool_calls_fixture [
    %{name: "extract_spec", arguments: %{"name" => "UserAuth", "priority" => "high"}}
  ]

  # ---------------------------------------------------------------------------
  # Authentication — no mock setup needed (auth fails before any mock call)
  # ---------------------------------------------------------------------------

  describe "POST /api/tools — authentication" do
    test "returns 401 when Authorization header is missing", %{conn: conn} do
      conn =
        post(conn, ~p"/api/tools", %{
          "provider" => "gemini-primary",
          "messages" => @valid_messages,
          "tools" => @valid_tools
        })

      assert json = json_response(conn, 401)
      assert json["error"] == "unauthorized"
    end

    test "returns 401 with unrecognized authorization scheme", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Token some-random-value")
        |> post(~p"/api/tools", %{
          "provider" => "gemini-primary",
          "messages" => @valid_messages,
          "tools" => @valid_tools
        })

      assert json_response(conn, 401)
    end
  end

  # ---------------------------------------------------------------------------
  # Input validation (auth stubbed to pass)
  # ---------------------------------------------------------------------------

  describe "POST /api/tools — input validation" do
    setup do
      stub(CortexCommunity.Users.Mock, :authenticate_by_api_key, fn _key ->
        {:ok, user_fixture()}
      end)

      :ok
    end

    test "returns 400 when messages is missing", %{conn: conn} do
      conn =
        conn
        |> with_auth()
        |> post(~p"/api/tools", %{"tools" => @valid_tools})

      assert json = json_response(conn, 400)
      assert json["message"] =~ "messages"
    end

    test "returns 400 when tools is missing", %{conn: conn} do
      conn =
        conn
        |> with_auth()
        |> post(~p"/api/tools", %{"messages" => @valid_messages})

      assert json = json_response(conn, 400)
      assert json["message"] =~ "tools"
    end

    test "returns 400 when both messages and tools are missing", %{conn: conn} do
      conn =
        conn
        |> with_auth()
        |> post(~p"/api/tools", %{})

      assert json = json_response(conn, 400)
      assert json["message"] =~ "messages"
    end
  end

  # ---------------------------------------------------------------------------
  # Core logic — provider routing and error handling
  # ---------------------------------------------------------------------------

  describe "POST /api/tools — provider routing" do
    setup do
      stub(CortexCommunity.Users.Mock, :authenticate_by_api_key, fn _key ->
        {:ok, user_fixture()}
      end)

      :ok
    end

    test "returns 503 when no workers have tools capability", %{conn: conn} do
      expect(CortexCore.Mock, :call_with_tools, fn _messages, _tools, _opts ->
        {:error, :no_workers_available}
      end)

      conn =
        conn
        |> with_auth()
        |> post(~p"/api/tools", %{
          "messages" => @valid_messages,
          "tools" => @valid_tools
        })

      assert json = json_response(conn, 503)
      assert json["message"] =~ "tool calling"
    end

    test "returns 400 when provider lacks tools capability", %{conn: conn} do
      expect(CortexCore.Mock, :call_with_tools, fn _messages, _tools, _opts ->
        {:error, {:worker_lacks_capability, "cohere-primary", :tools}}
      end)

      conn =
        conn
        |> with_auth()
        |> post(~p"/api/tools", %{
          "messages" => @valid_messages,
          "tools" => @valid_tools,
          "provider" => "cohere-primary"
        })

      assert json = json_response(conn, 400)
      assert json["message"] =~ "cohere-primary"
      assert json["message"] =~ "tool calling"
    end

    test "returns 404 when provider is not found", %{conn: conn} do
      expect(CortexCore.Mock, :call_with_tools, fn _messages, _tools, _opts ->
        {:error, {:provider_not_found, "nonexistent-provider"}}
      end)

      conn =
        conn
        |> with_auth()
        |> post(~p"/api/tools", %{
          "provider" => "nonexistent-provider",
          "messages" => @valid_messages,
          "tools" => @valid_tools
        })

      assert json = json_response(conn, 404)
      assert json["message"] =~ "nonexistent-provider"
    end

    test "returns 429 when provider is rate limited", %{conn: conn} do
      expect(CortexCore.Mock, :call_with_tools, fn _messages, _tools, _opts ->
        {:error, :rate_limited}
      end)

      conn =
        conn
        |> with_auth()
        |> post(~p"/api/tools", %{
          "provider" => "gemini-primary",
          "messages" => @valid_messages,
          "tools" => @valid_tools
        })

      assert json = json_response(conn, 429)
      assert json["message"] =~ "rate limited"
    end

    test "returns 502 when provider returns HTTP error", %{conn: conn} do
      expect(CortexCore.Mock, :call_with_tools, fn _messages, _tools, _opts ->
        {:error, {503, %{"error" => "service unavailable"}}}
      end)

      conn =
        conn
        |> with_auth()
        |> post(~p"/api/tools", %{
          "provider" => "gemini-primary",
          "messages" => @valid_messages,
          "tools" => @valid_tools
        })

      assert json = json_response(conn, 502)
      assert json["message"] =~ "503"
    end

    test "returns 500 on unexpected error", %{conn: conn} do
      expect(CortexCore.Mock, :call_with_tools, fn _messages, _tools, _opts ->
        {:error, :network_timeout}
      end)

      conn =
        conn
        |> with_auth()
        |> post(~p"/api/tools", %{
          "provider" => "gemini-primary",
          "messages" => @valid_messages,
          "tools" => @valid_tools
        })

      assert json_response(conn, 500)
    end
  end

  # ---------------------------------------------------------------------------
  # Success path — realistic fixture from actual Gemini/Groq responses
  # ---------------------------------------------------------------------------

  describe "POST /api/tools — success" do
    setup do
      stub(CortexCommunity.Users.Mock, :authenticate_by_api_key, fn _key ->
        {:ok, user_fixture()}
      end)

      :ok
    end

    test "returns tool_calls on successful extraction", %{conn: conn} do
      expect(CortexCore.Mock, :call_with_tools, fn _messages, _tools, _opts ->
        {:ok, @tool_calls_fixture}
      end)

      conn =
        conn
        |> with_auth()
        |> post(~p"/api/tools", %{
          "provider" => "gemini-primary",
          "messages" => @valid_messages,
          "tools" => @valid_tools
        })

      assert json = json_response(conn, 200)
      assert json["ok"] == true
      assert is_list(json["tool_calls"])
      assert length(json["tool_calls"]) == 1
    end

    test "returns empty tool_calls when provider found no tools to call", %{conn: conn} do
      expect(CortexCore.Mock, :call_with_tools, fn _messages, _tools, _opts ->
        {:ok, []}
      end)

      conn =
        conn
        |> with_auth()
        |> post(~p"/api/tools", %{
          "provider" => "groq-primary",
          "messages" => @valid_messages,
          "tools" => @valid_tools
        })

      assert json = json_response(conn, 200)
      assert json["ok"] == true
      assert json["tool_calls"] == []
    end

    test "forwards provider and model opts to cortex_core", %{conn: conn} do
      expect(CortexCore.Mock, :call_with_tools, fn _messages, _tools, opts ->
        assert Keyword.get(opts, :provider) == "groq-primary"
        assert Keyword.get(opts, :model) == "llama-3.3-70b-versatile"
        {:ok, @tool_calls_fixture}
      end)

      conn
      |> with_auth()
      |> post(~p"/api/tools", %{
        "provider" => "groq-primary",
        "model" => "llama-3.3-70b-versatile",
        "messages" => @valid_messages,
        "tools" => @valid_tools
      })
    end
  end
end
