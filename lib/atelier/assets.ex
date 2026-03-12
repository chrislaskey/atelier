defmodule Atelier.Assets do
  @moduledoc false
  import Plug.Conn

  # Read Phoenix framework JS at compile time (same pattern as phoenix_live_dashboard)
  phoenix_js_paths =
    for app <- [:phoenix, :phoenix_html, :phoenix_live_view] do
      path = Application.app_dir(app, ["priv", "static", "#{app}.js"])
      Module.put_attribute(__MODULE__, :external_resource, path)
      path
    end

  # Read pre-built Atelier JS at compile time
  js_path = Path.join(__DIR__, "../../dist/js/app.js")
  @external_resource js_path

  @js """
  #{for path <- phoenix_js_paths, do: path |> File.read!() |> String.replace("//# sourceMappingURL=", "// ")}
  #{File.read!(js_path)}
  """

  @hash Base.encode16(:crypto.hash(:md5, @js), case: :lower)

  def init(:js), do: :js

  def call(conn, :js) do
    conn
    |> put_resp_header("content-type", "text/javascript")
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
    |> put_private(:plug_skip_csrf_protection, true)
    |> send_resp(200, @js)
    |> halt()
  end

  @doc """
  Returns the current MD5 hash for the JS asset.
  """
  def current_hash(:js), do: @hash
end
