# Setup script: creates user, API key, and loads real OAuth credentials from Claude Code CLI
alias CortexCommunity.{Users, Credentials, Auth.ClaudeCliReader}

IO.puts("\nIniciando setup de Cortex...")

# Crear o recuperar usuario default
user = case Users.get_user_by_username("default") do
  nil ->
    {:ok, u} = Users.create_user(%{username: "default", name: "Default User"})
    IO.puts("\n✓ Usuario creado: #{u.username} (ID: #{u.id})")
    u
  existing ->
    IO.puts("\n✓ Usuario existente: #{existing.username} (ID: #{existing.id})")
    existing
end

# Crear API key
{:ok, api_key} = Users.create_api_key(user.id, %{name: "Default API Key"})
IO.puts("\n✓ API Key generado:")
IO.puts("  " <> IO.ANSI.bright() <> IO.ANSI.white() <> api_key.key <> IO.ANSI.reset())

# Leer credenciales reales del Claude Code CLI (Keychain o archivo)
IO.puts("\nLeyendo credenciales OAuth del Claude Code CLI...")

case ClaudeCliReader.read_credentials() do
  {:ok, real_creds} ->
    {:ok, _cred} = Credentials.store_credentials(user.id, "anthropic_cli", real_creds)
    sub_type = Map.get(real_creds, :subscription_type, "desconocida")
    IO.puts("✓ Credenciales OAuth reales guardadas (suscripción: #{sub_type})")

  {:error, reason} ->
    IO.puts(IO.ANSI.yellow() <> "⚠ No se encontraron credenciales OAuth: #{inspect(reason)}" <> IO.ANSI.reset())
    IO.puts(IO.ANSI.yellow() <> "  Asegúrate de tener Claude Code CLI autenticado." <> IO.ANSI.reset())
end

IO.puts("\n" <> IO.ANSI.green() <> "═══════════════════════════════════════" <> IO.ANSI.reset())
IO.puts(IO.ANSI.green() <> "✓ Setup manual completado!" <> IO.ANSI.reset())
IO.puts(IO.ANSI.green() <> "═══════════════════════════════════════" <> IO.ANSI.reset())
IO.puts("\n" <> IO.ANSI.cyan() <> "Usa este API key para probar:" <> IO.ANSI.reset())
IO.puts("  Authorization: Bearer " <> api_key.key)
IO.puts("")

# Guardar API key en un archivo temporal para usarlo en las pruebas
File.write!("/tmp/cortex_api_key.txt", api_key.key)
IO.puts(IO.ANSI.yellow() <> "💾 API key guardado en: /tmp/cortex_api_key.txt" <> IO.ANSI.reset())
IO.puts("")
