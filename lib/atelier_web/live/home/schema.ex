defmodule AtelierWeb.Live.Home.Index.Schema do
  use Ecto.Schema
  import Ecto.Changeset

  @models [
    "claude-sonnet-4-6",
    "claude-haiku-4-5-20251001",
    "claude-opus-4-6"
  ]

  def models, do: @models

  embedded_schema do
    field :name, :string, default: ""
    field :html, :string, default: ""
    field :elixir, :string, default: ""
    field :tsx, :string, default: ""
    field :prompt, :string, default: ""
    field :model, :string, default: "claude-sonnet-4-6"
    field :view_tabs, :string, default: "Preview"
  end

  def changeset(component \\ %__MODULE__{}, attrs) do
    component
    |> cast(attrs, [:name, :html, :elixir, :tsx, :prompt, :model, :view_tabs])
    |> validate_inclusion(:model, @models)
  end
end
