defmodule CortexCommunity.ModelDiscovery.ProviderModel do
  @moduledoc """
  Schema for tracking discovered models per worker.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "provider_models" do
    field(:worker_name, :string)
    field(:provider_type, :string)
    field(:active_model, :string)
    field(:discovered_models, {:array, :string}, default: [])
    field(:current_index, :integer, default: 0)
    field(:last_discovery_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  @required_fields [:worker_name, :provider_type]
  @optional_fields [:active_model, :discovered_models, :current_index, :last_discovery_at]

  def changeset(model, attrs) do
    model
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:worker_name)
  end
end
