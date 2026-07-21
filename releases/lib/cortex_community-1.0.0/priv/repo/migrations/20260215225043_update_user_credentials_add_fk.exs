defmodule CortexCommunity.Repo.Migrations.UpdateUserCredentialsAddFk do
  use Ecto.Migration

  def up do
    # Add foreign key constraint to existing user_id column
    alter table(:user_credentials) do
      modify :user_id, references(:cortex_users, type: :binary_id, on_delete: :delete_all)
    end
  end

  def down do
    # Remove foreign key constraint
    alter table(:user_credentials) do
      modify :user_id, :binary_id, null: false
    end
  end
end
