defmodule CortexCommunity.Auth.ThalamusClientTest do
  use ExUnit.Case, async: false
  alias CortexCommunity.Auth.ThalamusClient

  defmodule MockServer do
    use Plug.Router

    plug(:match)
    plug(:dispatch)

    post "/oauth/introspect" do
      handler =
        try do
          Agent.get(__MODULE__.Handler, & &1)
        rescue
          _ -> nil
        end

      if is_function(handler, 1) do
        handler.(conn)
      else
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"active" => false}))
      end
    end
  end

  setup do
    clean_ets!()

    # Store original auth config for cleanup
    original_auth = Application.get_env(:cortex_community, :auth)

    # Start an Agent to hold the current test handler (cross-process)
    {:ok, agent_pid} = Agent.start_link(fn -> nil end, name: MockServer.Handler)

    # Start mock HTTP server on a random port
    {:ok, _server} = Plug.Cowboy.http(MockServer, [], port: 0)
    port = :ranch.get_port(MockServer.HTTP)

    url = "http://localhost:#{port}/oauth/introspect"

    # Override auth config for test — preserve :mode from config/test.exs
    Application.put_env(:cortex_community, :auth,
      mode: :hybrid,
      thalamus_introspect_url: url,
      thalamus_client_id: "test-client-id",
      thalamus_client_secret: "test-client-secret",
      thalamus_cache_ttl: 60
    )

    on_exit(fn ->
      clean_ets!()
      Plug.Cowboy.shutdown(MockServer.HTTP)

      # Only stop Agent if still alive
      if Process.alive?(agent_pid) do
        Agent.stop(MockServer.Handler)
      end

      # Restore original auth config
      Application.put_env(:cortex_community, :auth, original_auth)
    end)

    {:ok, port: port, url: url}
  end

  defp clean_ets! do
    if :ets.whereis(:thalamus_introspect_cache) != :undefined do
      :ets.delete(:thalamus_introspect_cache)
    end
  end

  defp set_handler(fun) do
    Agent.update(MockServer.Handler, fn _ -> fun end)
  end

  # ---------------------------------------------------------------------------
  # Active token
  # ---------------------------------------------------------------------------

  describe "introspect/1 with active token" do
    test "returns claims when Thalamus responds with active: true" do
      claims = %{
        "active" => true,
        "sub" => "user-42",
        "scope" => "read write",
        "client_id" => "cortex"
      }

      set_handler(fn conn ->
        {:ok, _body, conn} = Plug.Conn.read_body(conn)

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(claims))
      end)

      assert {:ok, ^claims} = ThalamusClient.introspect("valid-jwt-token")
    end

    test "sends HTTP Basic auth with client_id:client_secret" do
      set_handler(fn conn ->
        [auth_header] = Plug.Conn.get_req_header(conn, "authorization")
        assert auth_header =~ "Basic "

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"active" => true}))
      end)

      assert {:ok, _} = ThalamusClient.introspect("token-xyz")
    end

    test "includes token in form-encoded body" do
      set_handler(fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ "token=my-secret-token"

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"active" => true}))
      end)

      assert {:ok, _} = ThalamusClient.introspect("my-secret-token")
    end
  end

  # ---------------------------------------------------------------------------
  # Inactive token
  # ---------------------------------------------------------------------------

  describe "introspect/1 with inactive token" do
    test "returns :inactive_token when Thalamus responds with active: false" do
      set_handler(fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"active" => false}))
      end)

      assert {:error, :inactive_token} = ThalamusClient.introspect("expired-token")
    end
  end

  # ---------------------------------------------------------------------------
  # Invalid credentials
  # ---------------------------------------------------------------------------

  describe "introspect/1 with invalid credentials" do
    test "returns :invalid_credentials on HTTP 401" do
      set_handler(fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(401, Jason.encode!(%{"error" => "invalid_client"}))
      end)

      assert {:error, :invalid_credentials} = ThalamusClient.introspect("any-token")
    end
  end

  # ---------------------------------------------------------------------------
  # Timeout
  # ---------------------------------------------------------------------------

  describe "introspect/1 timeout" do
    test "returns :timeout when the request exceeds 5 seconds" do
      set_handler(fn conn ->
        Process.sleep(6_000)

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"active" => true}))
      end)

      assert {:error, :timeout} = ThalamusClient.introspect("slow-token")
    end
  end

  # ---------------------------------------------------------------------------
  # Cache hit
  # ---------------------------------------------------------------------------

  describe "introspect/1 caching" do
    test "returns cached claims on second call without making an HTTP request" do
      claims = %{"active" => true, "sub" => "cached-user"}
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      set_handler(fn conn ->
        Agent.update(counter, &(&1 + 1))

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(claims))
      end)

      # First call — should hit the server
      assert {:ok, ^claims} = ThalamusClient.introspect("cacheable-token")
      # Second and third calls — should use cache
      assert {:ok, ^claims} = ThalamusClient.introspect("cacheable-token")
      assert {:ok, ^claims} = ThalamusClient.introspect("cacheable-token")

      # Exactly one HTTP request was made
      assert Agent.get(counter, & &1) == 1
    end
  end

  # ---------------------------------------------------------------------------
  # Invalid token input
  # ---------------------------------------------------------------------------

  describe "introspect/1 with invalid input" do
    test "returns :invalid_token for an empty string" do
      assert {:error, :invalid_token} = ThalamusClient.introspect("")
    end

    test "returns :invalid_token for non-string input" do
      assert {:error, :invalid_token} = ThalamusClient.introspect(nil)
      assert {:error, :invalid_token} = ThalamusClient.introspect(123)
    end
  end
end
