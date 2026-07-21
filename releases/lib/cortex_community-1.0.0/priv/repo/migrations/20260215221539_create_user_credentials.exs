defmodule CortexCommunity.Repo.Migrations.CreateUserCredentials do
  use Ecto.Migration

  def change do
    create table(:user_credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, :binary_id, null: false  # Will be FK after cortex_users is created
      add :provider, :string, null: false
      add :auth_type, :string, null: false  # "oauth", "api_key", "token"

      # Encrypted credentials data (JSON)
      add :encrypted_data, :binary, null: false

      # Metadata
      add :expires_at, :utc_datetime
      add :last_used_at, :utc_datetime
      add :is_active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:user_credentials, [:user_id])
    create index(:user_credentials, [:provider])
    create unique_index(:user_credentials, [:user_id, :provider])
  end
end
