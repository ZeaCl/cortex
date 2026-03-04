defmodule CortexCommunity.Repo.Migrations.CreateProviderModels do
  use Ecto.Migration

  def change do
    create table(:provider_models, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :worker_name, :string, null: false
      add :provider_type, :string, null: false
      add :active_model, :string
      add :discovered_models, {:array, :string}, default: []
      add :current_index, :integer, default: 0
      add :last_discovery_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:provider_models, [:worker_name])
    create index(:provider_models, [:provider_type])
  end
end
