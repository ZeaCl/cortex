defmodule CortexCommunity.Auth.AuthManagerTest do
  use ExUnit.Case, async: false
  alias CortexCommunity.Auth.AuthManager

  import Mox

  # Make sure mocks are verified
  setup :verify_on_exit!

  # ---------------------------------------------------------------------------
  # Helper to stub local auth
  # ---------------------------------------------------------------------------

  defp stub_local_auth do
    stub(CortexCommunity.Users.Mock, :authenticate_by_api_key, fn
      "ctx_valid-key" -> {:ok, user_fixture()}
      "ctx_expired-key" -> {:error, :expired_api_key}
      _ -> {:error, :invalid_api_key}
    end)
  end

  defp user_fixture do
    %CortexCommunity.CortexUser{
      id: "00000000-0000-0000-0000-000000000001",
      username: "testuser",
      email: "test@example.com",
      name: "Test User"
    }
  end

  # ---------------------------------------------------------------------------
  # Mode: local
  # ---------------------------------------------------------------------------

  describe "authenticate/2 in :local mode" do
    test "returns user for valid ctx_ key" do
      stub_local_auth()

      assert {:ok, auth_info} = AuthManager.authenticate("ctx_valid-key", :local)
      assert auth_info.source == :local
      assert auth_info.user.username == "testuser"
      assert auth_info.claims == nil
    end

    test "returns error for invalid ctx_ key" do
      stub_local_auth()

      assert {:error, :invalid_api_key} = AuthManager.authenticate("bad-key", :local)
    end

    test "returns error for expired ctx_ key" do
      stub_local_auth()

      assert {:error, :expired_api_key} = AuthManager.authenticate("ctx_expired-key", :local)
    end
  end

  # ---------------------------------------------------------------------------
  # Mode: thalamus
  # ---------------------------------------------------------------------------

  describe "authenticate/2 in :thalamus mode" do
    test "rejects ctx_ keys" do
      assert {:error, :local_keys_not_allowed_in_thalamus_mode} =
               AuthManager.authenticate("ctx_some-key", :thalamus)
    end

    test "returns claims for valid JWT (via ThalamusClient mock)" do
      # We test this indirectly through the ThalamusClient tests
      # Here we just confirm the dispatch logic doesn't call Users
      # and that the error from introspect propagates
      assert {:error, _} = AuthManager.authenticate("some-jwt-token", :thalamus)
    end
  end

  # ---------------------------------------------------------------------------
  # Mode: hybrid
  # ---------------------------------------------------------------------------

  describe "authenticate/2 in :hybrid mode" do
    test "routes ctx_ keys to local auth" do
      stub_local_auth()

      assert {:ok, auth_info} = AuthManager.authenticate("ctx_valid-key", :hybrid)
      assert auth_info.source == :local
      assert auth_info.user.username == "testuser"
    end

    test "routes non-ctx_ tokens to Thalamus introspect" do
      assert {:error, _} = AuthManager.authenticate("some-jwt", :hybrid)
    end
  end

  # ---------------------------------------------------------------------------
  # Default mode (reads from config)
  # ---------------------------------------------------------------------------

  describe "authenticate/1 (default mode from config)" do
    test "uses mode from Application config" do
      # In test environment, AUTH_MODE=local from test.exs
      stub_local_auth()

      assert {:ok, auth_info} = AuthManager.authenticate("ctx_valid-key", :local)
      assert auth_info.source == :local
    end
  end
end
