defmodule CortexCommunity.Repo.Migrations.CreateCortexApiKeys do
  use Ecto.Migration

  def change do
    create table(:cortex_api_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:cortex_users, type: :binary_id, on_delete: :delete_all), null: false

      # The actual API key (e.g., "ctx_abc123...")
      add :key, :string, null: false

      # Optional name for the API key (e.g., "Allisbox Production")
      add :name, :string

      # Security and usage tracking
      add :expires_at, :utc_datetime
      add :last_used_at, :utc_datetime
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:cortex_api_keys, [:key])
    create index(:cortex_api_keys, [:user_id])
    create index(:cortex_api_keys, [:is_active])
  end
end
