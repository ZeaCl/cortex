defmodule CortexCommunity.CortexApiKey do
  @moduledoc """
  Schema for Cortex API keys.

  > ⚠️ **Deprecated** — Use Thalamus OAuth2 tokens instead.
  > See `CortexCommunity.Auth.AuthManager` for the new authentication flow.
  > `ctx_` keys will be removed in a future version once all consumers migrate.

  API keys are used to authenticate requests from client applications (like Allisbox).
  Format: "ctx_" + base62 encoded random bytes (e.g., "ctx_4Kj9mN2pQ...")
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cortex_api_keys" do
    field(:key, :string)
    field(:name, :string)
    field(:expires_at, :utc_datetime)
    field(:last_used_at, :utc_datetime)
    field(:is_active, :boolean, default: true)

    belongs_to(:user, CortexCommunity.CortexUser, foreign_key: :user_id, type: :binary_id)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new API key.
  """
  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [:user_id, :key, :name, :expires_at, :is_active])
    |> validate_required([:user_id, :key])
    |> validate_format(:key, ~r/^ctx_[A-Za-z0-9]{32,}$/,
      message: "must be a valid Cortex API key"
    )
    |> unique_constraint(:key)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Generates a new API key string.

  Returns a string like "ctx_4Kj9mN2pQ8sL7vW..."
  """
  def generate_key do
    random_bytes = :crypto.strong_rand_bytes(24)

    encoded =
      Base.encode64(random_bytes, padding: false)
      |> String.replace(~r/[+\/=]/, fn
        "+" -> "a"
        "/" -> "b"
        "=" -> "c"
      end)

    "ctx_#{encoded}"
  end

  @doc """
  Creates a changeset for a new API key with auto-generated key.
  """
  def create_changeset(attrs) do
    attrs_with_key = Map.put(attrs, :key, generate_key())

    %__MODULE__{}
    |> changeset(attrs_with_key)
  end

  @doc """
  Checks if an API key is valid (active and not expired).
  """
  def valid?(%__MODULE__{is_active: false}), do: false
  def valid?(%__MODULE__{expires_at: nil}), do: true

  def valid?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :lt
  end

  @doc """
  Marks the API key as used (updates last_used_at).
  """
  def mark_as_used(%__MODULE__{} = api_key) do
    change(api_key, last_used_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
