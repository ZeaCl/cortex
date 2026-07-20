defmodule CortexCommunity.Release do
  @moduledoc """
  Release tasks for production deployment.

  Used to run database migrations in production without Mix.
  """
  @app :cortex_community

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
