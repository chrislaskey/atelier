defmodule Atelier.Web do
  @moduledoc false

  def live_view do
    quote do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller, only: [get_csrf_token: 0]

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.HTML
      import Atelier.Components.Core
      alias Phoenix.LiveView.JS
      alias Atelier.Components.Layouts
    end
  end

  @doc false
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
