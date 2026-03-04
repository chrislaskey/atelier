defmodule Atelier.Components do
  @template Path.join(__DIR__, "components/template.ex.eex")

  def write(%{name: name} = attrs) when name != "" do
    module_name = "AtelierWeb.Components." <> Macro.camelize(name)
    file_name = Macro.underscore(name) <> ".ex"
    dir = Path.join(File.cwd!(), "lib/atelier_web/components/atelier")
    path = Path.join(dir, file_name)

    File.mkdir_p!(dir)

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

  defp strip_defmodule(code) do
    code
    |> String.replace(~r/\A\s*defmodule\s+\S+\s+do\n/, "")
    |> String.replace(~r/\n\s*end\s*\z/, "")
    |> String.replace(~r/\A\s*use Phoenix\.Component\n*/, "")
    |> String.trim()
  end
end
