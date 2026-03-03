defmodule AtelierWeb.Live.Home.Index do
  use AtelierWeb, :live_view

  import AtelierWeb.Layouts

  alias AtelierWeb.Live.Home.Index.Schema

  @impl true
  def mount(_params, _session, socket) do
    form =
      %Schema{}
      |> Schema.changeset(%{})
      |> to_form()

    {:ok, assign(socket, form: form, preview_html: "")}
  end

  @impl true
  def handle_event("save", %{"schema" => params}, socket) do
    changeset = Schema.changeset(%Schema{}, params)

    case Ecto.Changeset.apply_action(changeset, :validate) do
      {:ok, schema} ->
        form =
          schema
          |> Schema.changeset(%{})
          |> to_form()

        {:noreply, assign(socket, form: form, preview_html: schema.html)}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
