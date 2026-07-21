# Test OAuth Client with Claude.ai

alias CortexCommunity.Clients.ClaudeOAuthClient
alias CortexCommunity.{Users, Credentials}

IO.puts("\n🧪 Testing OAuth Client for Claude.ai\n")

# Get the default user
case Users.get_user_by_username("default") do
  nil ->
    IO.puts("❌ No default user found. Run setup first: mix run priv/scripts/manual_setup.exs")
    System.halt(1)

  user ->
    IO.puts("✓ Found user: #{user.username}")

    # Get user's anthropic_cli credentials
    case Credentials.get_credentials(user.id, "anthropic_cli") do
      {:ok, creds} ->
        IO.puts("✓ Found anthropic_cli credentials")
        IO.puts("  Provider: #{creds.provider}")
        IO.puts("  Type: OAuth")

        # Check if valid
        if ClaudeOAuthClient.credentials_valid?(creds) do
          IO.puts("✓ Credentials are still valid")
        else
          IO.puts("⚠ Credentials have expired")
        end

        # Test message
        test_messages = [
          %{"role" => "user", "content" => "Say 'Hello from Cortex OAuth!' and nothing else."}
        ]

        IO.puts("\n📨 Making test request to Claude.ai via OAuth...")
        IO.puts("   This will use Claude Pro subscription (not API credits)\n")

        case ClaudeOAuthClient.chat(test_messages, creds, stream: false) do
          {:ok, response} ->
            IO.puts("✅ SUCCESS! Response received:")
            IO.puts(IO.ANSI.green() <> "   #{inspect(response, pretty: true)}" <> IO.ANSI.reset())

          {:error, :missing_access_token} ->
            IO.puts("❌ Missing access token in credentials")

          {:error, {:http_error, status, body}} ->
            IO.puts("❌ HTTP Error #{status}:")
            IO.puts("   #{body}")

            if status == 401 do
              IO.puts("\n💡 This usually means:")
              IO.puts("   - The OAuth token has expired")
              IO.puts("   - Run: claude setup-token (to refresh)")
            end

          {:error, {:request_failed, reason}} ->
            IO.puts("❌ Request failed: #{inspect(reason)}")

          {:error, reason} ->
            IO.puts("❌ Error: #{inspect(reason)}")
        end

      {:error, :not_found} ->
        IO.puts("❌ No anthropic_cli credentials found for this user")
        IO.puts("   Run: mix run priv/scripts/manual_setup.exs")

      {:error, reason} ->
        IO.puts("❌ Error getting credentials: #{inspect(reason)}")
    end
end

IO.puts("")
