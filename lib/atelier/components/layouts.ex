defmodule Atelier.Components.Layouts do
  @moduledoc false
  use Atelier.Web, :html

  @doc """
  Shows the flash group with standard titles and content.
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
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  attr :components, :list, required: true, doc: "tree of component nodes"
  attr :current, :string, default: nil, doc: "name of the currently selected component"
  attr :mount_path, :string, required: true, doc: "base path where Atelier is mounted"

  def sidebar(assigns) do
    ~H"""
    <nav class="w-80 shrink-0 bg-base-200 py-6 px-3" style="min-height: calc(100vh - 4rem);">
      <div class="w-full overflow-x-auto">
        <div class="font-bold mb-2 text-sm">Components</div>
        <ul :for={group <- @components} class="menu menu-xs w-full">
          <.dir_node node={group} current={@current} mount_path={@mount_path} />
        </ul>
      </div>
    </nav>
    """
  end

  attr :node, :map, required: true
  attr :current, :string, default: nil
  attr :mount_path, :string, required: true

  defp dir_node(assigns) do
    ~H"""
    <li>
      <details open>
        <summary>
          <.icon name="hero-folder" class="size-3" />
          <span class="whitespace-nowrap">{@node.label}</span>
        </summary>
        <ul>
          <li :for={file <- @node.files}>
            <.link patch={"#{@mount_path}/#{file.name}"} class={@current == file.name && "active"}>
              <.icon name="hero-document" class="size-3" />
              {file.filename}
            </.link>
          </li>
          <.dir_node :for={child <- @node.children} node={child} current={@current} mount_path={@mount_path} />
        </ul>
      </details>
    </li>
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
