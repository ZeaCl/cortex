defmodule CortexCommunity.ModelDiscovery.ModelRanking do
  @moduledoc """
  Schema for LLM-generated rankings by task type.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "model_rankings" do
    field(:task_type, :string)
    field(:ranked_workers, :map)
    field(:generated_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  @required_fields [:task_type, :ranked_workers]
  @optional_fields [:generated_at]

  def changeset(ranking, attrs) do
    ranking
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:task_type, [
      "chat",
      "coding",
      "reasoning",
      "tools",
      "long_context",
      "fast"
    ])
    |> unique_constraint(:task_type)
  end
end
