defmodule CortexCommunity.UserCredential do
  @moduledoc """
  Schema for storing user credentials for AI providers.

  Supports multiple authentication types:
  - OAuth tokens (from Claude Code CLI, etc.)
  - API keys
  - Session tokens
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_credentials" do
    # "anthropic_cli", "anthropic_api", "openai", etc.
    field(:provider, :string)
    # "oauth", "api_key", "token"
    field(:auth_type, :string)
    field(:encrypted_data, :binary)
    field(:expires_at, :utc_datetime)
    field(:last_used_at, :utc_datetime)
    field(:is_active, :boolean, default: true)

    belongs_to(:user, CortexCommunity.CortexUser, foreign_key: :user_id, type: :binary_id)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for user credentials.
  """
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [
      :user_id,
      :provider,
      :auth_type,
      :encrypted_data,
      :expires_at,
      :is_active,
      :last_used_at
    ])
    |> validate_required([:user_id, :provider, :auth_type, :encrypted_data])
    |> foreign_key_constraint(:user_id)
    |> validate_inclusion(:provider, [
      "anthropic_cli",
      "anthropic_api",
      "openai",
      "google",
      "groq",
      "github_copilot",
      "deepseek"
    ])
    |> validate_inclusion(:auth_type, ["oauth", "api_key", "token"])
    |> unique_constraint([:user_id, :provider])
  end

  @doc """
  Finds active credentials for a user and provider.
  """
  def find_by_user_and_provider(user_id, provider) do
    from(c in __MODULE__,
      where: c.user_id == ^user_id and c.provider == ^provider and c.is_active == true,
      order_by: [desc: c.inserted_at],
      limit: 1
    )
  end

  @doc """
  Checks if credentials are expired.
  """
  def expired?(%__MODULE__{expires_at: nil}), do: false

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Marks credentials as used (updates last_used_at).
  """
  def mark_as_used(%__MODULE__{} = credential) do
    credential
    |> changeset(%{last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)})
  end
end
