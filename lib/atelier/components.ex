defmodule Atelier.Components do
  @template Path.join(__DIR__, "components/template.ex.eex")

  @dir Path.join(File.cwd!(), "lib/atelier_web/components/atelier")

  def list do
    list_tree(@dir, "")
  end

  defp list_tree(dir, prefix) do
    case File.ls(dir) do
      {:ok, entries} ->
        entries = Enum.sort(entries)

        {dirs, files} =
          Enum.split_with(entries, &File.dir?(Path.join(dir, &1)))

        dir_nodes =
          Enum.flat_map(dirs, fn entry ->
            children = list_tree(Path.join(dir, entry), prefix <> entry <> "/")
            if children == [], do: [], else: [%{type: :dir, label: entry, children: children}]
          end)

        file_nodes =
          files
          |> Enum.filter(&String.ends_with?(&1, ".ex"))
          |> Enum.map(fn file ->
            leaf = String.trim_trailing(file, ".ex")
            %{type: :file, name: Macro.camelize(prefix <> leaf), label: leaf}
          end)

        dir_nodes ++ file_nodes

      {:error, _} ->
        []
    end
  end

  def read(name) do
    path = Path.join(@dir, Macro.underscore(name) <> ".ex")

    case File.read(path) do
      {:ok, content} ->
        metadata = load_metadata(name)

        {:ok,
         %{
           name: metadata[:name] || name,
           elixir: content,
           html: metadata[:html] || "",
           prompt: metadata[:prompt] || "",
           model: metadata[:model] || "claude-sonnet-4-6"
         }}

      {:error, _} ->
        :error
    end
  end

  def write(%{name: name} = attrs) when name != "" do
    module_name = "AtelierWeb.Components." <> Macro.camelize(name)
    file_name = Macro.underscore(name) <> ".ex"
    path = Path.join(@dir, file_name)

    File.mkdir_p!(Path.dirname(path))

    content =
      EEx.eval_file(@template,
        assigns:
          Map.merge(attrs, %{
            module_name: module_name,
            elixir: strip_defmodule(attrs.elixir),
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
    e -> {:error, Exception.message(e)}
  end

  defp load_metadata(name) do
    module = Module.concat(AtelierWeb.Components, Macro.camelize(name))

    if Code.ensure_loaded?(module) and function_exported?(module, :__atelier__, 0) do
      module.__atelier__()
    else
      %{}
    end
  end

  defp strip_defmodule(code) do
    code
    |> String.replace(~r/\A\s*defmodule\s+\S+\s+do\n/, "")
    |> String.replace(~r/\n\s*end\s*\z/, "")
    |> String.replace(~r/\A\s*use Phoenix\.Component\n*/, "")
    |> String.trim()
  end
end
