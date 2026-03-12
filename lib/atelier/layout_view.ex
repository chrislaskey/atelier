defmodule Atelier.LayoutView do
  @moduledoc false
  use Atelier.Web, :html

  embed_templates "layouts/*"

  def render("root.html", assigns), do: root(assigns)

  defp live_socket_path(conn) do
    [Enum.map(conn.script_name, &["/" | &1]) | conn.private.live_socket_path]
  end

  @compile {:no_warn_undefined, Phoenix.VerifiedRoutes}

  defp asset_path(conn, :js) do
    hash = Atelier.Assets.current_hash(:js)

    if function_exported?(conn.private.phoenix_router, :__atelier_prefix__, 0) do
      prefix = conn.private.phoenix_router.__atelier_prefix__()

      Phoenix.VerifiedRoutes.unverified_path(
        conn,
        conn.private.phoenix_router,
        "#{prefix}/js-#{hash}"
      )
    else
      "/js-#{hash}"
    end
  end
end
