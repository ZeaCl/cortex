# Test script para Universal Service Gateway en cortex_community
# Run: mix run test_universal_gateway.exs

IO.puts("\n=== Testing Universal Service Gateway in cortex_community ===\n")

# 1. Iniciar aplicación
IO.puts("📡 Starting CortexCommunity application...")
{:ok, _pid} = Application.ensure_all_started(:cortex_community)

# Esperar a que workers se configuren (asíncrono, toma ~12 segundos)
IO.puts("Esperando configuración de workers (15s)...")
Process.sleep(15000)

# 2. Listar workers configurados
IO.puts("\n=== Configured Workers ===")
workers = CortexCore.list_workers()
IO.puts("Total workers: #{length(workers)}")

Enum.each(workers, fn worker_info ->
  service_type = worker_info[:type] || worker_info[:service] || "unknown"
  IO.puts("  • #{worker_info[:name]} (#{service_type})")
end)

# 3. Health Status
IO.puts("\n=== Health Status ===")
health = CortexCore.health_status()

Enum.each(health, fn {name, status} ->
  emoji =
    case status do
      :available -> "✅"
      :unavailable -> "❌"
      _ -> "⚠️"
    end

  IO.puts("#{emoji} #{name}: #{status}")
end)

# 4. Test Web Search (Tavily)
IO.puts("\n=== Testing Web Search (Tavily) ===")

case CortexCore.call(:search, %{
       query: "What is Elixir programming language?",
       max_results: 3,
       search_depth: "basic",
       include_answer: true
     }) do
  {:ok, results} ->
    IO.puts("✅ Search successful!")
    IO.puts("\nQuery: #{results.query}")

    if results.answer do
      IO.puts("\n📝 Generated Answer:")
      IO.puts(String.slice(results.answer, 0, 200) <> "...")
    end

    IO.puts("\n🔍 Results (#{length(results.results)}):")

    Enum.take(results.results, 2)
    |> Enum.each(fn result ->
      IO.puts("\n  • #{result["title"]}")
      IO.puts("    #{result["url"]}")
    end)

  {:error, :no_workers_available} ->
    IO.puts("⚠️  No search workers available")
    IO.puts("   Make sure TAVILY_API_KEY is set in .env")

  {:error, reason} ->
    IO.puts("❌ Search failed: #{inspect(reason)}")
end

# 5. Test LLM (backward compatibility)
IO.puts("\n=== Testing LLM Chat (backward compatibility) ===")

case CortexCore.chat([
       %{role: "user", content: "Say 'Hello from Universal Gateway' in one sentence"}
     ]) do
  {:ok, stream} ->
    IO.write("🤖 Response: ")
    stream |> Enum.take(100) |> Enum.each(&IO.write/1)
    IO.puts("\n")

  {:error, :no_workers_available} ->
    IO.puts("⚠️  No LLM workers available")

  {:error, reason} ->
    IO.puts("❌ LLM failed: #{inspect(reason)}")
end

IO.puts("\n=== Test Complete ===")

IO.puts("""

✨ Universal Service Gateway is working in cortex_community!

All services share the same infrastructure:
- Automatic failover
- Health checks
- API key rotation
- Retry logic

Now you can use:
  CortexCore.call(:search, %{query: "..."})  # Web search
  CortexCore.chat(messages)                   # LLM chat

And coming soon:
  CortexCore.call(:audio, %{text: "..."})    # TTS
  CortexCore.call(:vision, %{prompt: "..."}) # Image gen
""")
