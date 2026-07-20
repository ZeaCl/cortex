defmodule Mix.Tasks.Cortex.Keygen do
  @moduledoc """
  > ⚠️ **Deprecated** — Use Thalamus OAuth2 tokens instead.
  > See `docs/AUTHENTICATION.md` for migration guide.

  Genera una API key persistente para un proyecto que consume Cortex.

  ## Uso

      mix cortex.keygen <nombre-proyecto>

  ## Ejemplos

      mix cortex.keygen allisbox-production
      mix cortex.keygen mi-app-dev

  La key generada no caduca y puede guardarse en el `.env` del proyecto:

      CORTEX_API_KEY=ctx_xxxxxxxxxxxxxxxx
      CORTEX_URL=http://localhost:4000/api/chat
  """

  use Mix.Task

  @shortdoc "[DEPRECATED] Genera una API key para un proyecto cliente de Cortex"

  @impl Mix.Task
  def run([]) do
    print_deprecation_banner()

    IO.puts("❌ Debes especificar un nombre para el proyecto.")
    IO.puts("   Uso: mix cortex.keygen <nombre-proyecto>")
    IO.puts("   Ejemplo: mix cortex.keygen allisbox-production\n")
  end

  def run([project_name | _]) do
    print_deprecation_banner()
    Mix.Task.run("app.start")

    alias CortexCommunity.Users

    {:ok, user} = Users.get_or_create_default_user()

    case Users.create_api_key(user.id, %{name: project_name}) do
      {:ok, api_key} ->
        IO.puts("""

        ✅ API key generada para: #{project_name}
        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        #{api_key.key}

        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Agrega esto al .env del proyecto:

          CORTEX_API_KEY=#{api_key.key}
          CORTEX_URL=http://localhost:4000/api/chat

        ⚠  Guarda esta key — no se puede recuperar después.

        📢 Esta key usa el formato legacy ctx_. Se recomienda migrar a
           Thalamus OAuth2. Ver docs/AUTHENTICATION.md
        """)

      {:error, changeset} ->
        IO.puts("\n❌ Error generando la key:")
        IO.puts(inspect(changeset.errors))
    end
  end

  defp print_deprecation_banner do
    IO.puts("""

    ╔══════════════════════════════════════════════════════════════╗
    ║  ⚠️  DEPRECATED: ctx_ API keys will be phased out.           ║
    ║  Migrate to Thalamus OAuth2 tokens for authentication.       ║
    ║  See docs/AUTHENTICATION.md for migration guide.             ║
    ╚══════════════════════════════════════════════════════════════╝
    """)
  end
end
