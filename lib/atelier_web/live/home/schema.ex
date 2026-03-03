defmodule AtelierWeb.Live.Home.Index.Schema do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :html, :string, default: ""
  end

  def changeset(component \\ %__MODULE__{}, attrs) do
    cast(component, attrs, [:html])
  end
end
