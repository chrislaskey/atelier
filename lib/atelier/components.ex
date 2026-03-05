defmodule Atelier.Components do
  @template Path.join(__DIR__, "components/template.ex.eex")

  @dir Path.join(File.cwd!(), "lib/atelier_web/components/atelier")

  def list do
    node = list_tree(@dir, "")

    if node.files == [] and node.children == [] do
      []
    else
      [node]
    end
  end

  defp list_tree(dir, prefix) do
    case File.ls(dir) do
      {:ok, entries} ->
        entries = Enum.sort(entries)

        {dirs, files} =
          Enum.split_with(entries, &File.dir?(Path.join(dir, &1)))

        file_nodes =
          files
          |> Enum.filter(&String.ends_with?(&1, ".ex"))
          |> Enum.map(fn file ->
            %{name: prefix <> file, filename: file}
          end)

        children =
          dirs
          |> Enum.map(fn entry ->
            list_tree(Path.join(dir, entry), prefix <> entry <> "/")
          end)
          |> Enum.reject(fn node -> node.files == [] and node.children == [] end)

        label =
          if prefix == "" do
            Path.relative_to(@dir, File.cwd!()) <> "/"
          else
            prefix |> String.trim_trailing("/") |> Path.basename()
          end

        %{label: label, files: file_nodes, children: children}

      {:error, _} ->
        %{label: "", files: [], children: []}
    end
  end

  def read(name) do
    path = Path.join(@dir, name)

    case File.read(path) do
      {:ok, content} ->
        metadata = load_metadata(name)

        {:ok,
         %{
           name: name,
           elixir: extract_user_code(content),
           html: metadata[:html] || "",
           tsx: extract_tsx(content),
           file_content: content,
           updated_at: metadata[:updated_at]
         }}

      {:error, _} ->
        :error
    end
  end

  def introspect(name) do
    stem = String.trim_trailing(name, ".ex")
    module = Module.concat(AtelierWeb.Components, Macro.camelize(stem))
    func = stem |> Path.basename() |> String.to_atom()

    if Code.ensure_loaded?(module) and function_exported?(module, :__components__, 0) do
      case module.__components__() do
        %{^func => %{attrs: attrs, slots: slots}} ->
          attrs =
            attrs
            |> Enum.reject(&(&1.type == :global))
            |> Enum.map(fn attr ->
              %{
                name: attr.name,
                type: attr.type,
                required: attr.required,
                default: attr.opts[:default],
                values: attr.opts[:values]
              }
            end)

          %{attrs: attrs, slots: slots}

        _ ->
          nil
      end
    end
  end

  def write(%{name: name} = attrs) when name != "" do
    name = if String.ends_with?(name, ".ex"), do: name, else: name <> ".ex"
    stem = String.trim_trailing(name, ".ex")
    module_name = "AtelierWeb.Components." <> Macro.camelize(stem)
    path = Path.join(@dir, name)

    File.mkdir_p!(Path.dirname(path))

    content =
      EEx.eval_file(@template,
        assigns:
          Map.merge(attrs, %{
            module_name: module_name,
            elixir: indent(extract_user_code(attrs.elixir), 2),
            html_heredoc: indent(Map.get(attrs, :html, ""), 4),
            tsx: Map.get(attrs, :tsx, ""),
            tsx_heredoc: indent(Map.get(attrs, :tsx, ""), 6),
            js_export_name: stem |> Macro.camelize() |> String.replace(".", ""),
            updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
          })
      )

    case compile_check(content, path) do
      :ok ->
        File.write!(path, content)
        {:ok, path}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def write(_), do: :skip

  defp compile_check(content, path) do
    Code.compile_string(content, path)
    :ok
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp load_metadata(name) do
    stem = String.trim_trailing(name, ".ex")
    module = Module.concat(AtelierWeb.Components, Macro.camelize(stem))

    if Code.ensure_loaded?(module) do
      metadata =
        if function_exported?(module, :metadata, 0),
          do: module.metadata(),
          else: %{}

      html =
        if function_exported?(module, :html, 0),
          do: module.html() |> String.trim(),
          else: ""

      Map.put(metadata, :html, html)
    else
      %{}
    end
  end

  defp indent(text, spaces) do
    prefix = String.duplicate(" ", spaces)

    text
    |> String.split("\n")
    |> Enum.map_join("\n", &(prefix <> &1))
  end

  defp extract_tsx(content) do
    case Regex.run(~r/<script[^>]*extension="tsx"[^>]*>\n(.*?)\n\s*<\/script>/s, content) do
      [_, tsx] -> dedent(tsx)
      _ -> ""
    end
  end

  defp dedent(text) do
    lines = String.split(text, "\n")

    min_indent =
      lines
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.map(fn line ->
        String.length(line) - String.length(String.trim_leading(line))
      end)
      |> Enum.min(fn -> 0 end)

    lines
    |> Enum.map_join("\n", fn line ->
      if String.trim(line) == "", do: "", else: String.slice(line, min_indent..-1//1)
    end)
    |> String.trim()
  end

  defp extract_user_code(code) do
    code
    # Strip leading blank line (from old template comment)
    |> String.replace(~r/\A\n/, "")
    # Strip defmodule wrapper (only strip closing end if defmodule was present)
    |> then(fn code ->
      if Regex.match?(~r/\A\s*defmodule\s+/, code) do
        code
        |> String.replace(~r/\A\s*defmodule\s+\S+\s+do\n/, "")
        |> String.replace(~r/\n\s*end\s*\z/, "")
      else
        code
      end
    end)
    # Strip use declarations
    |> String.replace(~r/^\s*use AtelierWeb, :live_component\n*/m, "")
    |> String.replace(~r/^\s*use Phoenix\.Component\n*/m, "")
    # Strip @moduledoc heredoc
    |> String.replace(~r/^\s*@moduledoc\s+""".+?"""\n*/ms, "")
    # Strip @metadata block
    |> String.replace(~r/^\s*@metadata\s+%\{.+?^\s*\}\n*/ms, "")
    # Strip def metadata
    |> String.replace(~r/^\s*def metadata.*\n*/m, "")
    # Strip def html do...end
    |> String.replace(~r/^\s*def html do.+?^\s*end\n*/ms, "")
    # Strip def tsx(assigns) ColocatedJS block
    |> String.replace(~r/^\s*def tsx\(assigns\) do.+?^\s*end\n*/ms, "")
    |> String.trim()
  end
end
