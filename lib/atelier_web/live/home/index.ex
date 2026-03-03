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

    {:ok, assign(socket, form: form, preview_document: "")}
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

        {:noreply,
         assign(socket, form: form, preview_document: build_preview_document(schema.html))}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp build_preview_document(html) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <link href="https://cdn.jsdelivr.net/npm/daisyui@5" rel="stylesheet" type="text/css" />
      <link href="https://cdn.jsdelivr.net/npm/daisyui@5/themes.css" rel="stylesheet" type="text/css" />
      <script src="https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4"></script>
      <script>
        const t = window.parent.document.documentElement.getAttribute("data-theme");
        if (t) document.documentElement.setAttribute("data-theme", t);
        window.addEventListener("message", (e) => {
          if (e.data && e.data.type === "theme-change")
            document.documentElement.setAttribute("data-theme", e.data.theme);
        });
      </script>
    </head>
    <body class="p-6">
      #{html}
    </body>
    </html>
    """
  end
end
