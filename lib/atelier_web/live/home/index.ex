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

    {:ok,
     socket
     |> allow_upload(:design_image,
       accept: ~w(.png .jpg .jpeg .gif .webp),
       max_entries: 1,
       max_file_size: 5_000_000
     )
     |> assign(
       form: form,
       preview_document: "",
       loading: nil,
       loading_tsx: false,
       history: [],
       history_index: 0,
       components: Atelier.Components.list(),
       current_component: nil,
       file_content: nil,
       file_updated_at: nil,
       component_render_fn: nil,
       component_attrs: nil,
       preview_assigns: %{}
     )}
  end

  @impl true
  def handle_params(%{"path" => [name]}, uri, socket) do
    socket = assign(socket, :uri, uri)

    case Atelier.Components.read(name) do
      {:ok, data} ->
        form =
          %Schema{}
          |> Schema.changeset(%{
            "name" => data.name,
            "html" => data.html,
            "elixir" => data.elixir,
            "tsx" => data.tsx
          })
          |> to_form()

        {:noreply,
         assign(socket,
           current_component: name,
           form: form,
           preview_document: build_preview_document(data.html),
           file_content: data.file_content,
           file_updated_at: data.updated_at,
           component_render_fn: resolve_render_fn(name),
           component_attrs: Atelier.Components.introspect(name),
           preview_assigns: build_default_preview_assigns(Atelier.Components.introspect(name)),
           history: [],
           history_index: 0
         )}

      :error ->
        {:noreply,
         assign(socket,
           current_component: name,
           file_content: nil,
           file_updated_at: nil,
           component_render_fn: nil,
           component_attrs: nil,
           preview_assigns: %{},
           history: [],
           history_index: 0
         )}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     assign(socket,
       current_component: nil,
       file_content: nil,
       file_updated_at: nil,
       component_render_fn: nil,
       component_attrs: nil,
       preview_assigns: %{},
       history: [],
       history_index: 0
     )}
  end

  @impl true
  def handle_event("validate", %{"schema" => schema_params} = _params, socket) do
    changeset = Schema.changeset(%Schema{}, schema_params)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("preview-change", %{"preview" => params}, socket) do
    {:noreply, assign(socket, preview_assigns: params)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :design_image, ref)}
  end

  def handle_event("save", %{"schema" => schema_params} = _params, socket) do
    changeset = Schema.changeset(%Schema{}, schema_params)

    case Ecto.Changeset.apply_action(changeset, :validate) do
      {:ok, schema} ->
        form =
          schema
          |> Schema.changeset(%{})
          |> to_form()

        active_tab =
          case schema_params["view_tabs"] do
            "preview" -> "prompt"
            value -> String.downcase(value)
          end

        socket =
          case active_tab do
            "html" ->
              socket
              |> assign(
                form: form,
                preview_document: build_preview_document(schema.html),
                loading: :elixir
              )
              |> start_async(:generate_elixir, fn ->
                convert_html_to_elixir(schema.html, schema.elixir, schema.model)
              end)

            "elixir" ->
              socket
              |> assign(form: form, loading: :html, loading_tsx: true)
              |> start_async(:generate_html, fn ->
                convert_elixir_to_html(schema.elixir, schema.html, schema.model)
              end)
              |> start_async(:generate_tsx, fn ->
                convert_elixir_to_tsx(schema.elixir, schema.tsx, schema.html, schema.model)
              end)

            "tsx" ->
              socket
              |> assign(form: form, loading: :elixir)
              |> start_async(:generate_elixir_from_tsx, fn ->
                convert_tsx_to_elixir(schema.tsx, schema.elixir, schema.html, schema.model)
              end)

            "prompt" ->
              image_data =
                consume_uploaded_entries(socket, :design_image, fn %{path: path}, entry ->
                  {:ok, %{base64: Base.encode64(File.read!(path)), media_type: entry.client_type}}
                end)
                |> List.first()

              socket
              |> assign(form: form, loading: :elixir)
              |> start_async(:prompt_generate_elixir, fn ->
                apply_prompt(schema.prompt, schema.elixir, schema.html, schema.model, image_data)
              end)
          end

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("restore-history", %{"entries" => entries}, socket) when is_list(entries) do
    history = Enum.take(entries, 10)

    case history do
      [latest | _] ->
        if file_is_newer?(socket.assigns.file_updated_at, latest["timestamp"]) do
          {:noreply, assign(socket, history: history, history_index: 0)}
        else
          form = build_form_from_snapshot(latest)
          preview = build_preview_document(latest["html"] || "")

          {:noreply,
           assign(socket,
             history: history,
             history_index: 0,
             form: form,
             preview_document: preview
           )}
        end

      [] ->
        {:noreply, socket}
    end
  end

  def handle_event("select-snapshot", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    snapshot = Enum.at(socket.assigns.history, index)

    if snapshot do
      form = build_form_from_snapshot(snapshot)
      preview = build_preview_document(snapshot["html"] || "")
      {:noreply, assign(socket, form: form, preview_document: preview, history_index: index)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("clear-history", _params, socket) do
    {:noreply,
     socket
     |> assign(history: [], history_index: 0)
     |> push_event("persist-history", %{entries: []})}
  end

  def handle_event("write", _params, socket) do
    schema = socket.assigns.form.source |> Ecto.Changeset.apply_changes()

    socket =
      case Atelier.Components.write(%{
             name: schema.name,
             html: schema.html,
             elixir: schema.elixir,
             tsx: schema.tsx
           }) do
        {:ok, path} ->
          socket
          |> put_flash(:info, "Wrote #{path}")
          |> assign(components: Atelier.Components.list())

        {:error, reason} ->
          put_flash(socket, :error, reason)

        :skip ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_async(:generate_elixir, {:ok, {:ok, result}}, socket) do
    form = update_form_field(socket.assigns.form, :elixir, result)
    schema = form.source |> Ecto.Changeset.apply_changes()

    {:noreply,
     socket
     |> assign(form: form, loading: nil, loading_tsx: true)
     |> start_async(:generate_tsx, fn ->
       convert_elixir_to_tsx(result, schema.tsx, schema.html, schema.model)
     end)
     |> maybe_push_snapshot()}
  end

  def handle_async(:generate_elixir, {:ok, {:error, reason}}, socket) do
    form = update_form_field(socket.assigns.form, :elixir, "Error: #{inspect(reason)}")
    {:noreply, assign(socket, form: form, loading: nil)}
  end

  def handle_async(:generate_elixir, {:exit, reason}, socket) do
    form = update_form_field(socket.assigns.form, :elixir, "Error: #{inspect(reason)}")
    {:noreply, assign(socket, form: form, loading: nil)}
  end

  def handle_async(:prompt_generate_elixir, {:ok, {:ok, result}}, socket) do
    form = update_form_field(socket.assigns.form, :elixir, result)
    schema = form.source |> Ecto.Changeset.apply_changes()

    {:noreply,
     socket
     |> assign(form: form, loading: :html, loading_tsx: true)
     |> start_async(:generate_html, fn ->
       convert_elixir_to_html(result, schema.html, schema.model)
     end)
     |> start_async(:generate_tsx, fn ->
       convert_elixir_to_tsx(result, schema.tsx, schema.html, schema.model)
     end)}
  end

  def handle_async(:prompt_generate_elixir, {:ok, {:error, reason}}, socket) do
    form = update_form_field(socket.assigns.form, :elixir, "Error: #{inspect(reason)}")
    {:noreply, assign(socket, form: form, loading: nil)}
  end

  def handle_async(:prompt_generate_elixir, {:exit, reason}, socket) do
    form = update_form_field(socket.assigns.form, :elixir, "Error: #{inspect(reason)}")
    {:noreply, assign(socket, form: form, loading: nil)}
  end

  def handle_async(:generate_html, {:ok, {:ok, result}}, socket) do
    form = update_form_field(socket.assigns.form, :html, result)

    {:noreply,
     socket
     |> assign(form: form, preview_document: build_preview_document(result), loading: nil)
     |> maybe_push_snapshot()}
  end

  def handle_async(:generate_html, {:ok, {:error, reason}}, socket) do
    form = update_form_field(socket.assigns.form, :html, "Error: #{inspect(reason)}")
    {:noreply, assign(socket, form: form, loading: nil)}
  end

  def handle_async(:generate_html, {:exit, reason}, socket) do
    form = update_form_field(socket.assigns.form, :html, "Error: #{inspect(reason)}")
    {:noreply, assign(socket, form: form, loading: nil)}
  end

  def handle_async(:generate_tsx, {:ok, {:ok, result}}, socket) do
    form = update_form_field(socket.assigns.form, :tsx, result)

    {:noreply,
     socket
     |> assign(form: form, loading_tsx: false)
     |> maybe_push_snapshot()}
  end

  def handle_async(:generate_tsx, {:ok, {:error, reason}}, socket) do
    form = update_form_field(socket.assigns.form, :tsx, "Error: #{inspect(reason)}")
    {:noreply, assign(socket, form: form, loading_tsx: false)}
  end

  def handle_async(:generate_tsx, {:exit, reason}, socket) do
    form = update_form_field(socket.assigns.form, :tsx, "Error: #{inspect(reason)}")
    {:noreply, assign(socket, form: form, loading_tsx: false)}
  end

  def handle_async(:generate_elixir_from_tsx, {:ok, {:ok, result}}, socket) do
    form = update_form_field(socket.assigns.form, :elixir, result)
    schema = form.source |> Ecto.Changeset.apply_changes()

    {:noreply,
     socket
     |> assign(form: form, loading: :html)
     |> start_async(:generate_html, fn ->
       convert_elixir_to_html(result, schema.html, schema.model)
     end)}
  end

  def handle_async(:generate_elixir_from_tsx, {:ok, {:error, reason}}, socket) do
    form = update_form_field(socket.assigns.form, :elixir, "Error: #{inspect(reason)}")
    {:noreply, assign(socket, form: form, loading: nil)}
  end

  def handle_async(:generate_elixir_from_tsx, {:exit, reason}, socket) do
    form = update_form_field(socket.assigns.form, :elixir, "Error: #{inspect(reason)}")
    {:noreply, assign(socket, form: form, loading: nil)}
  end

  defp maybe_push_snapshot(socket) do
    if socket.assigns.loading == nil and not socket.assigns.loading_tsx do
      push_snapshot(socket)
    else
      socket
    end
  end

  defp push_snapshot(socket) do
    schema = socket.assigns.form.source |> Ecto.Changeset.apply_changes()

    snapshot = %{
      "name" => schema.name,
      "html" => schema.html,
      "elixir" => schema.elixir,
      "tsx" => schema.tsx,
      "prompt" => schema.prompt,
      "model" => schema.model,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    history = Enum.take([snapshot | socket.assigns.history], 10)

    socket
    |> assign(history: history, history_index: 0)
    |> push_event("persist-history", %{entries: history})
  end

  defp build_form_from_snapshot(snapshot) do
    %Schema{}
    |> Schema.changeset(%{
      "name" => snapshot["name"] || "",
      "html" => snapshot["html"] || "",
      "elixir" => snapshot["elixir"] || "",
      "tsx" => snapshot["tsx"] || "",
      "prompt" => snapshot["prompt"] || "",
      "model" => snapshot["model"] || "claude-sonnet-4-6"
    })
    |> to_form()
  end

  defp file_is_newer?(nil, _history_timestamp), do: false
  defp file_is_newer?(_file_timestamp, nil), do: true

  defp file_is_newer?(file_timestamp, history_timestamp) do
    file_timestamp > history_timestamp
  end

  defp format_timestamp(nil), do: "Unknown"

  defp format_timestamp(timestamp_str) do
    case DateTime.from_iso8601(timestamp_str) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%-I:%M:%S %p UTC")
      _ -> timestamp_str
    end
  end

  defp resolve_render_fn(name) do
    module = Module.concat(AtelierWeb.Components, Macro.camelize(name))
    func = name |> String.split(".") |> List.last() |> Macro.underscore() |> String.to_atom()

    if Code.ensure_loaded?(module) and function_exported?(module, func, 1) do
      Function.capture(module, func, 1)
    end
  end

  defp build_default_preview_assigns(nil), do: %{}

  defp build_default_preview_assigns(%{attrs: attrs}) do
    defaults =
      Map.new(attrs, fn attr ->
        value =
          case attr.default do
            nil -> ""
            v when is_binary(v) or is_number(v) or is_boolean(v) or is_atom(v) -> to_string(v)
            other -> inspect(other)
          end

        {to_string(attr.name), value}
      end)

    Map.put(defaults, "inner_block_text", "Hello")
  end

  defp cast_preview_assigns(preview_assigns, component_attrs) do
    if component_attrs == nil do
      %{}
    else
      Enum.reduce(component_attrs.attrs, %{}, fn attr, acc ->
        raw = Map.get(preview_assigns, to_string(attr.name))

        value =
          case attr.type do
            :boolean -> raw == "true"
            :integer -> parse_int(raw)
            :float -> parse_float(raw)
            type when type in [:list, :map, :any] -> attr.default
            _ -> if raw == "", do: nil, else: raw
          end

        Map.put(acc, attr.name, value)
      end)
    end
  end

  defp parse_int(nil), do: nil

  defp parse_int(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_float(nil), do: nil

  defp parse_float(s) do
    case Float.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp update_form_field(form, field, value) do
    form.source
    |> Ecto.Changeset.apply_changes()
    |> Map.put(field, value)
    |> Schema.changeset(%{})
    |> to_form()
  end

  defp apply_prompt(prompt, existing_elixir, existing_html, model, image_data) do
    user_content =
      if existing_elixir != "" do
        """
        Apply this change to the Phoenix functional component:

        #{prompt}

        Existing Elixir component:

        #{existing_elixir}

        Existing HTML for reference:

        #{existing_html}
        """
      else
        """
        Create a Phoenix functional component based on this description:

        #{prompt}
        """
      end

    content =
      case image_data do
        %{base64: b64, media_type: mt} ->
          [
            %{type: "image", source: %{type: "base64", media_type: mt, data: b64}},
            %{type: "text", text: user_content}
          ]

        _ ->
          user_content
      end

    params = %{
      model: model,
      max_tokens: 4096,
      system:
        "You are an expert Elixir and Phoenix developer. Apply the described change to the Phoenix functional component using MODERN 2026 HEEx syntax. In addition to `def` functions, define `attr` and `slot` annotations as needed. Return only the raw code. No markdown, no backtick fences, no explanation.",
      messages: [
        %{
          role: "user",
          content: content
        }
      ]
    }

    case Atelier.AI.create_message(params) do
      {:ok, %{"content" => [%{"text" => text} | _]}} -> {:ok, strip_code_fences(text)}
      {:ok, response} -> {:error, "Unexpected response: #{inspect(response)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp convert_html_to_elixir(html, existing_elixir, model) do
    user_content =
      if existing_elixir != "" do
        """
        Update this Phoenix functional component to match the new HTML. Keep changes minimal — preserve existing structure, naming, attrs, and slots where possible.

        Existing Elixir component:

        #{existing_elixir}

        New HTML:

        #{html}
        """
      else
        "Convert this HTML to a reusable Phoenix functional component:\n\n#{html}"
      end

    params = %{
      model: model,
      max_tokens: 4096,
      system:
        "You are an expert Elixir and Phoenix developer. Convert the given HTML into a reusable Phoenix functional component using MODERN 2026 HEEx syntax. In addition to `def` functions, define `attr` and `slot` annotations as needed. Return only the raw code. No markdown, no backtick fences, no explanation.",
      messages: [
        %{
          role: "user",
          content: user_content
        }
      ]
    }

    case Atelier.AI.create_message(params) do
      {:ok, %{"content" => [%{"text" => text} | _]}} -> {:ok, strip_code_fences(text)}
      {:ok, response} -> {:error, "Unexpected response: #{inspect(response)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp convert_elixir_to_html(elixir, existing_html, model) do
    user_content =
      if existing_html != "" do
        """
        Update this HTML to match the new Phoenix/HEEx component. Keep changes minimal — preserve existing structure, classes, and formatting where possible.

        Existing HTML:

        #{existing_html}

        New Elixir component:

        #{elixir}
        """
      else
        "Convert this Phoenix/HEEx component to plain HTML with DaisyUI (preferred) and Tailwind classes:\n\n#{elixir}"
      end

    params = %{
      model: model,
      max_tokens: 4096,
      system:
        "You are an expert Elixir and Phoenix developer. Convert the given Phoenix/HEEx component into well-formatted, properly indented HTML with DaisyUI (preferred) and Tailwind CSS classes. Return only the raw HTML. No markdown, no backtick fences, no explanation.",
      messages: [
        %{
          role: "user",
          content: user_content
        }
      ]
    }

    case Atelier.AI.create_message(params) do
      {:ok, %{"content" => [%{"text" => text} | _]}} -> {:ok, strip_code_fences(text)}
      {:ok, response} -> {:error, "Unexpected response: #{inspect(response)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp convert_elixir_to_tsx(elixir, existing_tsx, html, model) do
    user_content =
      if existing_tsx != "" do
        """
        Update this React component to match the new Phoenix/HEEx component. Keep changes minimal — preserve existing structure, props, and naming where possible.

        Existing React component:

        #{existing_tsx}

        New Elixir component:

        #{elixir}

        HTML for reference:

        #{html}
        """
      else
        """
        Convert this Phoenix/HEEx component to a React functional component with TSX.

        Elixir component:

        #{elixir}

        HTML for reference:

        #{html}
        """
      end

    params = %{
      model: model,
      max_tokens: 4096,
      system:
        "You are an expert React and Phoenix developer. Convert the given Phoenix/HEEx component into an equivalent React functional component using TSX. Use the same DaisyUI (preferred) and Tailwind CSS classes. Map Phoenix attrs to React props with sensible defaults. Export the component as the default export. Return only the raw TSX code. No markdown, no backtick fences, no explanation.",
      messages: [
        %{
          role: "user",
          content: user_content
        }
      ]
    }

    case Atelier.AI.create_message(params) do
      {:ok, %{"content" => [%{"text" => text} | _]}} -> {:ok, strip_code_fences(text)}
      {:ok, response} -> {:error, "Unexpected response: #{inspect(response)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp convert_tsx_to_elixir(tsx, existing_elixir, _html, model) do
    user_content =
      if existing_elixir != "" do
        """
        Update this Phoenix functional component to match the new React/TSX component. Keep changes minimal — preserve existing structure, naming, attrs, and slots where possible.

        Existing Elixir component:

        #{existing_elixir}

        New React/TSX component:

        #{tsx}
        """
      else
        "Convert this React/TSX component to a reusable Phoenix functional component:\n\n#{tsx}"
      end

    params = %{
      model: model,
      max_tokens: 4096,
      system:
        "You are an expert Elixir and Phoenix developer. Convert the given React/TSX component into a reusable Phoenix functional component using MODERN 2026 HEEx syntax. In addition to `def` functions, define `attr` and `slot` annotations as needed. Return only the raw code. No markdown, no backtick fences, no explanation.",
      messages: [
        %{
          role: "user",
          content: user_content
        }
      ]
    }

    case Atelier.AI.create_message(params) do
      {:ok, %{"content" => [%{"text" => text} | _]}} -> {:ok, strip_code_fences(text)}
      {:ok, response} -> {:error, "Unexpected response: #{inspect(response)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp upload_error_to_string(:too_large), do: "Image too large (max 5 MB)"
  defp upload_error_to_string(:not_accepted), do: "Invalid file type"
  defp upload_error_to_string(:too_many_files), do: "Only one image allowed"

  defp strip_code_fences(text) do
    text
    |> String.replace(~r/\A```\w*\n/, "")
    |> String.replace(~r/\n```\s*\z/, "")
    |> String.trim()
  end

  defp build_preview_document(html) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <link href="https://cdn.jsdelivr.net/npm/daisyui@5" rel="stylesheet" type="text/css" />
      <link href="https://cdn.jsdelivr.net/npm/daisyui@5/themes.css" rel="stylesheet" type="text/css" />
      <link href="/assets/css/app.css" rel="stylesheet" type="text/css" />
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
