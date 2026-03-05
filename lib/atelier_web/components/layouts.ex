defmodule AtelierWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use AtelierWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <.theme_selector />
          </li>
          <li>
            <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  attr :components, :list, required: true, doc: "tree of component nodes"
  attr :current, :string, default: nil, doc: "name of the currently selected component"

  def sidebar(assigns) do
    ~H"""
    <nav class="w-80 shrink-0 bg-base-200 py-8 px-6">
      <div class="w-full overflow-x-auto">
        <div class="font-bold mb-2 text-sm">Components</div>
        <ul :for={group <- @components} class="menu menu-xs w-full">
          <li>
            <details open>
              <summary>
                <.icon name="hero-folder" class="size-3" />
                <span class="whitespace-nowrap">{group.path}</span>
              </summary>
              <ul>
                <li :for={file <- group.files}>
                  <.link patch={"/#{file.name}"} class={@current == file.name && "active"}>
                    <.icon name="hero-document-text" class="size-3" />
                    {file.filename}
                  </.link>
                </li>
              </ul>
            </details>
          </li>
        </ul>
      </div>
    </nav>
    """
  end

  @themes [
    "light",
    "dark",
    "retro",
    "cyberpunk",
    "valentine",
    "aqua",
    "dracula",
    "nord",
    "synthwave",
    "night",
    "coffee",
    "forest",
    "cupcake",
    "pastel",
    "caramellatte",
    "sunset"
  ]

  @doc """
  Provides a dropdown theme selector based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  attr :themes, :list, default: @themes

  attr :preview_only, :boolean,
    default: false,
    doc: "when true, only changes the preview iframe theme"

  def theme_selector(assigns) do
    assigns =
      assign(
        assigns,
        :controller_class,
        if(assigns.preview_only, do: "preview-theme", else: "theme-controller")
      )

    ~H"""
    <div class="dropdown dropdown-end">
      <div tabindex="0" role="button" class="btn btn-ghost">
        <.icon name="hero-swatch-micro" class="size-4" /> Theme
        <svg
          width="12px"
          height="12px"
          class="inline-block h-2 w-2 fill-current opacity-60"
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 2048 2048"
        >
          <path d="M1799 349l242 241-1017 1017L7 590l242-241 775 775 775-775z"></path>
        </svg>
      </div>
      <ul
        tabindex="0"
        class="dropdown-content bg-base-300 rounded-box z-10 w-52 p-2 shadow-2xl max-h-80 overflow-y-auto"
      >
        <li :for={theme <- @themes}>
          <input
            type="radio"
            name="theme-dropdown"
            class={[@controller_class, "w-full btn btn-sm btn-block btn-ghost justify-start"]}
            aria-label={String.capitalize(theme)}
            value={theme}
          />
        </li>
      </ul>
    </div>
    """
  end
end
