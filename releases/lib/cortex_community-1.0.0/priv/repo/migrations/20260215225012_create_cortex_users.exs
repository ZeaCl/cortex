defmodule CortexCommunity.Repo.Migrations.CreateCortexUsers do
  use Ecto.Migration

  def change do
    create table(:cortex_users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :username, :string, null: false
      add :email, :string
      add :name, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:cortex_users, [:username])
    create index(:cortex_users, [:email])
  end
end
