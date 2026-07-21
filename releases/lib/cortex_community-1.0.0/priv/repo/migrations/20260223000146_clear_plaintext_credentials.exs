defmodule CortexCommunity.Repo.Migrations.ClearPlaintextCredentials do
  use Ecto.Migration

  def up do
    # Clear all stored credentials so they are re-encrypted on next server startup.
    # This is required because credentials were previously stored as plain JSON.
    # The auto_setup in Application will re-read and re-store them encrypted.
    execute "DELETE FROM user_credentials"
  end

  def down do
    # No-op: cannot restore plaintext data
    :ok
  end
end
