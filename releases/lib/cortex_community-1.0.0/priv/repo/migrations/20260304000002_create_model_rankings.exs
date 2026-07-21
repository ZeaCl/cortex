defmodule CortexCommunity.Repo.Migrations.CreateModelRankings do
  use Ecto.Migration

  def change do
    create table(:model_rankings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :task_type, :string, null: false
      add :ranked_workers, :map, null: false
      add :generated_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:model_rankings, [:task_type])
  end
end
