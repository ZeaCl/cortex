defmodule CortexCommunityWeb.ChatControllerTest do
  use CortexCommunityWeb.ConnCase

  # ---------------------------------------------------------------------------
  # Authentication tests — no mock setup needed (auth fails before any mock call)
  # ---------------------------------------------------------------------------

  describe "POST /api/chat — authentication" do
    test "returns 401 when Authorization header is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/chat", %{"messages" => [%{"role" => "user", "content" => "hi"}]})
      assert json = json_response(conn, 401)
      assert json["error"] == "unauthorized"
    end

    test "returns 401 with unrecognized authorization scheme", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Token some-random-value")
        |> post(~p"/api/chat", %{"messages" => [%{"role" => "user", "content" => "hi"}]})

      assert json_response(conn, 401)
    end

    test "returns 401 when API key is invalid", %{conn: conn} do
      expect(CortexCommunity.Users.Mock, :authenticate_by_api_key, fn _key ->
        {:error, :invalid_api_key}
      end)

      conn =
        conn
        |> with_auth()
        |> post(~p"/api/chat", %{"messages" => [%{"role" => "user", "content" => "hi"}]})

      assert json = json_response(conn, 401)
      assert json["message"] =~ "Invalid API key"
    end

    test "returns 401 when API key is expired", %{conn: conn} do
      expect(CortexCommunity.Users.Mock, :authenticate_by_api_key, fn _key ->
        {:error, :expired_api_key}
      end)

      conn =
        conn
        |> with_auth()
        |> post(~p"/api/chat", %{"messages" => [%{"role" => "user", "content" => "hi"}]})

      assert json = json_response(conn, 401)
      assert json["message"] =~ "expired"
    end
  end

  # ---------------------------------------------------------------------------
  # Input validation — auth stubbed, controller logic exercised
  # ---------------------------------------------------------------------------

  describe "POST /api/chat — input validation" do
    setup do
      stub(CortexCommunity.Users.Mock, :authenticate_by_api_key, fn _key ->
        {:ok, user_fixture()}
      end)

      :ok
    end

    test "returns 400 when messages field is missing", %{conn: conn} do
      conn =
        conn
        |> with_auth()
        |> post(~p"/api/chat", %{})

      assert json = json_response(conn, 400)
      assert json["message"] =~ "messages"
    end

    test "returns 400 when messages is not an array", %{conn: conn} do
      conn =
        conn
        |> with_auth()
        |> post(~p"/api/chat", %{"messages" => "not an array"})

      assert json = json_response(conn, 400)
      assert json["message"] =~ "array"
    end
  end

  # ---------------------------------------------------------------------------
  # Server-credentials path (no anthropic provider → falls back to server pool)
  # Mock responses are based on actual responses captured from the live system.
  # ---------------------------------------------------------------------------

  describe "POST /api/chat — server credentials path" do
    setup do
      stub(CortexCommunity.Users.Mock, :authenticate_by_api_key, fn _key ->
        {:ok, user_fixture()}
      end)

      :ok
    end

    test "streams SSE chunks and done event on success", %{conn: conn} do
      # Realistic fixture: list simulates a token stream from Gemini/Groq
      expect(CortexCore.Mock, :chat, fn _messages, _opts ->
        {:ok, ["Hello", ", ", "world", "!"]}
      end)

      conn =
        conn
        |> with_auth()
        |> post(~p"/api/chat", %{"messages" => [%{"role" => "user", "content" => "hi"}]})

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/event-stream"]

      body = response(conn, 200)
      assert body =~ ~s("content":"Hello")
      assert body =~ ~s("content":"world")
      assert body =~ "event: done"
      assert body =~ ~s("done":true)
    end

    test "returns 503 when no workers available", %{conn: conn} do
      expect(CortexCore.Mock, :chat, fn _messages, _opts ->
        {:error, :no_workers_available}
      end)

      conn =
        conn
        |> with_auth()
        |> post(~p"/api/chat", %{"messages" => [%{"role" => "user", "content" => "hi"}]})

      # Content-type stays text/event-stream (set before dispatch); read body directly
      assert conn.status == 503
      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert json["message"] =~ "No AI workers"
    end

    test "returns 500 when all workers failed with details", %{conn: conn} do
      # Realistic error: all providers returned errors
      expect(CortexCore.Mock, :chat, fn _messages, _opts ->
        {:error,
         {:all_workers_failed,
          [
            {"gemini-primary", "rate_limited"},
            {"groq-primary", "context_length_exceeded"}
          ]}}
      end)

      conn =
        conn
        |> with_auth()
        |> post(~p"/api/chat", %{"messages" => [%{"role" => "user", "content" => "hi"}]})

      # Content-type stays text/event-stream (set before dispatch); read body directly
      assert conn.status == 500
      assert {:ok, json} = Jason.decode(conn.resp_body)
      assert json["error"] == true
      assert json["message"] == "All AI providers failed"
      assert json["details"] =~ "gemini-primary"
    end

    test "returns 500 on generic error", %{conn: conn} do
      expect(CortexCore.Mock, :chat, fn _messages, _opts ->
        {:error, :timeout}
      end)

      conn =
        conn
        |> with_auth()
        |> post(~p"/api/chat", %{"messages" => [%{"role" => "user", "content" => "hi"}]})

      assert conn.status == 500
    end

    test "forwards provider option to cortex_core", %{conn: conn} do
      expect(CortexCore.Mock, :chat, fn _messages, opts ->
        assert Keyword.get(opts, :provider) == "groq-primary"
        {:ok, ["ok"]}
      end)

      conn
      |> with_auth()
      |> post(~p"/api/chat", %{
        "messages" => [%{"role" => "user", "content" => "hi"}],
        "provider" => "groq-primary"
      })

      # verify_on_exit! will confirm the expect was satisfied
    end

    test "forwards model option to cortex_core", %{conn: conn} do
      expect(CortexCore.Mock, :chat, fn _messages, opts ->
        assert Keyword.get(opts, :model) == "llama-3.3-70b-versatile"
        {:ok, ["ok"]}
      end)

      conn
      |> with_auth()
      |> post(~p"/api/chat", %{
        "messages" => [%{"role" => "user", "content" => "hi"}],
        "model" => "llama-3.3-70b-versatile"
      })
    end
  end
end
