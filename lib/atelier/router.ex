defmodule Atelier.Router do
  @moduledoc """
  Provides LiveView routing for Atelier.

  ## Usage

      defmodule MyAppWeb.Router do
        use Phoenix.Router
        import Atelier.Router

        scope "/dev" do
          pipe_through :browser
          atelier "/atelier"
        end
      end

  ## Options

    * `:live_socket_path` - Configures the socket path. It must match
      the `socket "/live", Phoenix.LiveView.Socket` in your endpoint.
      Defaults to `"/live"`.

    * `:on_mount` - Declares a custom list of `Phoenix.LiveView.on_mount/1`
      callbacks to add to the live session. Useful for authentication.

    * `:csp_nonce_assign_key` - An assign key to find the CSP nonce value
      used for assets. Supports either `atom()` or a map of
      `%{optional(:script) => atom(), optional(:style) => atom()}`.
  """

  defmacro atelier(path, opts \\ []) do
    opts =
      if Macro.quoted_literal?(opts) do
        Macro.prewalk(opts, &expand_alias(&1, __CALLER__))
      else
        opts
      end

    quote bind_quoted: binding() do
      scope path, alias: false, as: false do
        {session_name, session_opts, route_opts} =
          Atelier.Router.__options__(opts)

        import Phoenix.Router, only: [get: 4]
        import Phoenix.LiveView.Router, only: [live: 4, live_session: 3]

        live_session session_name, session_opts do
          # Atelier assets
          get "/js-:md5", Atelier.Assets, :js, as: :atelier_asset

          # Routes
          live "/", Atelier.AtelierLive, :home, route_opts
          live "/*path", Atelier.AtelierLive, :page, route_opts
        end
      end

      unless Module.get_attribute(__MODULE__, :atelier_prefix) do
        @atelier_prefix Phoenix.Router.scoped_path(__MODULE__, path)
                        |> String.replace_suffix("/", "")
        def __atelier_prefix__, do: @atelier_prefix
      end
    end
  end

  defp expand_alias({:__aliases__, _, _} = alias, env),
    do: Macro.expand(alias, %{env | function: {:atelier, 2}})

  defp expand_alias(other, _env), do: other

  @doc false
  def __options__(options) do
    live_socket_path = Keyword.get(options, :live_socket_path, "/live")

    csp_nonce_assign_key =
      case options[:csp_nonce_assign_key] do
        nil -> nil
        key when is_atom(key) -> %{style: key, script: key}
        %{} = keys -> Map.take(keys, [:style, :script])
      end

    {
      options[:live_session_name] || :atelier,
      [
        session: {__MODULE__, :__session__, [csp_nonce_assign_key]},
        root_layout: {Atelier.LayoutView, :root},
        on_mount: options[:on_mount] || nil
      ],
      [
        private: %{
          live_socket_path: live_socket_path,
          csp_nonce_assign_key: csp_nonce_assign_key
        },
        as: :atelier
      ]
    }
  end

  @doc false
  def __session__(conn, csp_nonce_assign_key) do
    %{
      "csp_nonces" => %{
        style: get_in_assigns(conn, csp_nonce_assign_key, :style),
        script: get_in_assigns(conn, csp_nonce_assign_key, :script)
      }
    }
  end

  defp get_in_assigns(_conn, nil, _type), do: nil
  defp get_in_assigns(conn, keys, type), do: conn.assigns[keys[type]]
end
