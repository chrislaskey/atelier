# Atelier: Embeddable Library Implementation Plan

## Overview

Convert Atelier from a standalone Phoenix application into an embeddable library that can be mounted inside any existing Phoenix LiveView application — similar to how `phoenix_live_dashboard` works.

### User Experience (Goal)

```elixir
# 1. Add to mix.exs
{:atelier, "~> 0.1.0"}

# 2. Add config (config/dev.exs)
config :atelier,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  components_dir: "lib/my_app_web/components/atelier",
  web_module: MyAppWeb

# 3. Add route (lib/my_app_web/router.ex)
import Atelier.Router

scope "/dev" do
  pipe_through :browser
  atelier "/atelier"
end
```

---

## Part 1: Package Structure

### 1.1 — `mix.exs` Changes

Transform from a full Phoenix app into a library package.

**Current:** Full Phoenix app with Ecto, Swoosh, Bandit, DNS cluster, etc.

**Target:** Minimal library with only essential deps.

```elixir
defmodule Atelier.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/..."

  def project do
    [
      app: :atelier,
      version: @version,
      elixir: "~> 1.15",
      # No compilers needed — host app handles LiveView compilation
      # No listeners needed
      package: package(),
      deps: deps(),
      # Include dist/ for pre-built JS
      elixirc_paths: ["lib"]
    ]
  end

  # Library does NOT start an OTP application by default.
  # No endpoint, no repo, no supervision tree needed.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_html, "~> 4.1"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.2"},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      # Dev/build only
      {:esbuild, "~> 0.10", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: ~w(lib dist mix.exs README.md LICENSE.md),
      # dist/ contains pre-built JS assets
    ]
  end
end
```

**Key decisions:**
- `phoenix` is NOT a direct dep — `phoenix_live_view` pulls it in, and we only need component/LV features
- `req` stays — needed for the Anthropic API client
- `heroicons` stays — included in all modern LiveView releases, fine as a dep
- No Ecto, no Swoosh, no Bandit, no Tailwind
- `esbuild` is dev-only for building JS into `dist/`
- CSS comes from CDN (no build step for CSS)

### 1.2 — Directory Restructure

```
lib/
├── atelier.ex                          # Public API & configuration
├── atelier/
│   ├── router.ex                       # Router macro (atelier/2)
│   ├── layout_view.ex                  # Root layout for embedded rendering
│   ├── layouts/
│   │   └── root.html.heex             # Self-contained HTML shell
│   ├── live/
│   │   ├── atelier_live.ex            # Main LiveView (renamed from Home.Index)
│   │   └── atelier_live.html.heex     # Template
│   ├── components/
│   │   ├── core_components.ex         # UI components (scoped)
│   │   └── layouts.ex                 # App-level layout (sidebar, header, etc.)
│   ├── controllers/
│   │   └── assets.ex                  # Plug to serve JS assets
│   ├── ai.ex                          # AI behaviour
│   ├── ai/
│   │   └── client.ex                  # Anthropic API client
│   ├── components_manager.ex          # File system ops (renamed from components.ex)
│   └── components/
│       └── template.ex.eex            # Component template
dist/
├── js/
│   └── app.js                         # Pre-built JS (hooks, topbar, etc.)
assets/
├── js/
│   └── app.js                         # Source JS (dev only, builds to dist/)
│   └── vendor/
│       └── topbar.js
```

**Key decisions:**
- All modules move under `Atelier.*` namespace (no more `AtelierWeb.*`)
- Components (CoreComponents, Layouts) become internal to the library
- `dist/` contains pre-built assets shipped with the hex package
- The `assets/` directory is dev-only for building

---

## Part 2: Router Macro

### 2.1 — `Atelier.Router`

Following the `phoenix_live_dashboard` pattern exactly:

```elixir
defmodule Atelier.Router do
  @moduledoc """
  Provides LiveView routing for Atelier.
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
    end
  end

  def __options__(options) do
    live_socket_path = Keyword.get(options, :live_socket_path, "/live")
    csp_nonce_assign_key = options[:csp_nonce_assign_key]

    session_args = [
      csp_nonce_assign_key
    ]

    {
      options[:live_session_name] || :atelier,
      [
        session: {__MODULE__, :__session__, session_args},
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

  def __session__(conn, csp_nonce_assign_key) do
    %{
      "csp_nonces" => %{
        style: conn.assigns[csp_nonce_assign_key],
        script: conn.assigns[csp_nonce_assign_key]
      }
    }
  end
end
```

**Key points:**
- No CSS asset route needed — CSS comes from CDN
- Only one JS asset route
- Catch-all route (`/*path`) for component navigation
- Session carries minimal data (just CSP nonces)
- Configuration comes from application env, not session

---

## Part 3: Layout & Asset Serving

### 3.1 — Root Layout (`Atelier.LayoutView` + `root.html.heex`)

The root layout renders a complete HTML document, just like `phoenix_live_dashboard`:

```heex
<!DOCTYPE html>
<html lang="en" phx-socket={live_socket_path(@conn)}>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
    <title>Atelier</title>

    <!-- DaisyUI + Tailwind from CDN -->
    <link href="https://cdn.jsdelivr.net/npm/daisyui@5" rel="stylesheet" type="text/css" />
    <link href="https://cdn.jsdelivr.net/npm/daisyui@5/themes.css" rel="stylesheet" type="text/css" />
    <script src="https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4"></script>

    <!-- Atelier JS (bundled, served from library) -->
    <script defer src={asset_path(@conn, :js)}></script>

    <!-- Theme persistence (inline) -->
    <script>
      // ... theme localStorage logic (same as current root.html.heex)
    </script>
  </head>
  <body>
    {@inner_content}
  </body>
</html>
```

**Why a full HTML document?**
This is the same approach `phoenix_live_dashboard` uses. The `root_layout` in `live_session` renders a complete `<html>` document. The host app's layout is NOT used — Atelier brings its own complete page shell. This is necessary because:
- We need specific CDN links (DaisyUI, Tailwind browser build)
- We need our own JS (with hooks)
- We need theme management scripts
- We don't want to conflict with the host app's styles

### 3.2 — Asset Serving (`Atelier.Assets`)

Follow the same compile-time embedding pattern as `phoenix_live_dashboard`:

```elixir
defmodule Atelier.Assets do
  @moduledoc false
  import Plug.Conn

  # Read pre-built JS at compile time
  js_path = Path.join(__DIR__, "../../dist/js/app.js")
  @external_resource js_path

  # Concatenate Phoenix framework JS + our JS
  phoenix_js_paths =
    for app <- [:phoenix, :phoenix_html, :phoenix_live_view] do
      path = Application.app_dir(app, ["priv", "static", "#{app}.js"])
      Module.put_attribute(__MODULE__, :external_resource, path)
      path
    end

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

  def current_hash(:js), do: @hash
end
```

**Key difference from LiveDashboard:** No CSS asset serving. CSS comes entirely from CDN.

### 3.3 — JS Build Pipeline

The `assets/js/app.js` needs to be restructured for embedded use:

**Current `app.js`:** Creates its own `LiveSocket` and connects it.

**Embedded `app.js`:** Must create its own `LiveSocket` (like LiveDashboard does), since it runs in its own root layout with its own HTML document.

```javascript
// dist/js/app.js (built from assets/js/app.js)

import topbar from "./vendor/topbar"

// LiveDashboard pattern: get socket path from HTML attribute
let socketPath = document.querySelector("html").getAttribute("phx-socket") || "/live"
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let liveSocket = new LiveView.LiveSocket(socketPath, Phoenix.Socket, {
  params: {_csrf_token: csrfToken},
  longPollFallbackMs: 2500,
  // Hooks are registered here — see Part 4
  hooks: { ...window.Atelier?.customHooks }
})

// Progress bar
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()
window.liveSocket = liveSocket
```

**Build step** (dev only, produces `dist/js/app.js`):

```bash
esbuild assets/js/app.js --bundle --minify --outdir=dist/js
```

Note: The Phoenix framework JS (`phoenix.js`, `phoenix_html.js`, `phoenix_live_view.js`) is concatenated at compile time by the `Assets` module (same as LiveDashboard), NOT by esbuild. This ensures the correct versions from the host app's dependencies are used.

---

## Part 4: JavaScript Hooks

### 4.1 — Current Hook Inventory

1. **Colocated hooks** (defined in HEEx templates via `phoenix-colocated`):
   - `.PasteUpload` — handles paste/drop file uploads
   - `.FormHistory` — persists form state to localStorage

2. **Vendor scripts:**
   - `topbar.js` — progress bar (used in JS, not a hook)

### 4.2 — Strategy: Colocated Hooks Should Work As-Is

Since Atelier writes component files directly into the host app's filetree, and the host app's `app.js` already imports `phoenix-colocated` hooks, our colocated hooks defined in HEEx templates should be discovered and loaded by the host app's build pipeline automatically.

**How it works today:**
- `app.js` imports `colocated, {hooks as colocatedHooks} from "phoenix-colocated/atelier"`
- The build-time colocated hook system scans HEEx templates in the project
- Hooks defined with `<script :type={Phoenix.LiveView.ColocatedHook}>` in our templates get picked up

**In the embedded context:**
- Atelier's LiveView templates live in `deps/atelier/lib/...`
- The host app's `phoenix-colocated` import scans for hooks across the project (including deps)
- This needs to be verified — if `phoenix-colocated` only scans the host's own `lib/`, we may need the `runtime` variant

**Fallback — runtime colocated hooks:**
If build-time colocated hooks aren't discovered from deps, we switch to the `runtime` attribute:

```heex
<script :type={Phoenix.LiveView.ColocatedHook} name=".PasteUpload" runtime>
  {
    mounted() {
      // ... paste/drop upload logic
    }
  }
</script>
```

Runtime colocated hooks are sent as part of the LiveView payload (no build step needed), making them fully self-contained. This is likely the more robust approach for a library.

**Secondary fallback — LiveDashboard hook pattern:**
If neither colocated approach works, we bundle hooks in the JS served by `Atelier.Assets`:

1. Define hooks in `assets/js/hooks/` and import them in `app.js`
2. Register them on the `LiveSocket` in our embedded JS bundle
3. Reference in templates by plain name (`phx-hook="PasteUpload"`)

> **ACTION ITEM:** Test colocated hooks early in Phase 1 to determine which approach to use. Start with runtime colocated hooks as the most likely winner for a library context.

---

## Part 5: Configuration

### 5.1 — Application Configuration

All configuration lives in the host app's config:

```elixir
# config/dev.exs
config :atelier,
  # Required: Anthropic API key for AI features
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),

  # Required: the host app's web module (e.g., MyAppWeb)
  # Used to derive components_dir and module prefix for generated components
  web_module: MyAppWeb,

  # Optional: directory where components are stored
  # Defaults to "lib/<web_module_snake>/components/atelier/"
  components_dir: "lib/my_app_web/components/atelier",

  # Optional: default AI model
  model: "claude-sonnet-4-6"
```

### 5.2 — Configuration Module

```elixir
defmodule Atelier do
  @moduledoc """
  Atelier - Interactive component builder for Phoenix LiveView.
  """

  def anthropic_api_key do
    Application.get_env(:atelier, :anthropic_api_key) ||
      raise "Missing :anthropic_api_key config for :atelier"
  end

  def web_module do
    Application.get_env(:atelier, :web_module) ||
      raise "Missing :web_module config for :atelier. " <>
            "Set it to your Phoenix web module, e.g., MyAppWeb"
  end

  def components_dir do
    Application.get_env(:atelier, :components_dir) ||
      default_components_dir()
  end

  def components_module_prefix do
    Module.concat(web_module(), "Components")
  end

  defp default_components_dir do
    # Derive from web_module: MyAppWeb -> "lib/my_app_web/components/atelier"
    web_snake = web_module() |> Module.split() |> Enum.join(".") |> Macro.underscore()
    Path.join(File.cwd!(), "lib/#{web_snake}/components/atelier")
  end
end
```

The `web_module` config is the key integration point. It drives:
- **Components directory** — defaults to `lib/<web_module_snake>/components/atelier/`
- **Module prefix** — generated components use `<WebModule>.Components.Button`, etc.
- **Template `use` statement** — generated components use `use Phoenix.Component`
  (not a host-specific macro, keeping generated code portable)

### 5.3 — Router-level Options

Some options can also be passed directly to the `atelier/2` macro:

```elixir
atelier "/atelier",
  live_socket_path: "/live",           # default: "/live"
  csp_nonce_assign_key: :csp_nonce,    # for CSP support
  on_mount: [MyApp.AuthHook]           # custom on_mount hooks (e.g., auth)
```

---

## Part 6: Module Renaming & Namespace

### 6.1 — Module Mapping

| Current (standalone)                      | Library                          |
|------------------------------------------|----------------------------------|
| `AtelierWeb`                              | `Atelier.Web` (internal helpers) |
| `AtelierWeb.Router`                       | `Atelier.Router`                 |
| `AtelierWeb.Layouts`                      | `Atelier.LayoutView` + `Atelier.Components.Layouts` |
| `AtelierWeb.CoreComponents`               | `Atelier.Components.Core`       |
| `AtelierWeb.Live.Home.Index`              | `Atelier.AtelierLive`           |
| `AtelierWeb.Live.Home.Index.Schema`       | `Atelier.AtelierLive.Schema`    |
| `AtelierWeb.Endpoint`                     | REMOVED (use host's endpoint)   |
| `AtelierWeb.Telemetry`                    | REMOVED                         |
| `AtelierWeb.Gettext`                      | REMOVED or `Atelier.Gettext`    |
| `Atelier.Application`                     | REMOVED (no supervision tree)   |
| `Atelier.Repo`                            | REMOVED                         |
| `Atelier.Mailer`                          | REMOVED                         |
| `Atelier.Components`                      | `Atelier.ComponentsManager`     |
| `Atelier.AI`                              | `Atelier.AI`                    |
| `Atelier.AI.Client`                       | `Atelier.AI.Client`             |

### 6.2 — Internal Web Helpers

Replace `use AtelierWeb, :live_view` etc. with an internal module:

```elixir
defmodule Atelier.Web do
  @moduledoc false

  def live_view do
    quote do
      use Phoenix.LiveView
      import Phoenix.HTML
      import Atelier.Components.Core
      alias Phoenix.LiveView.JS
      alias Atelier.Components.Layouts
    end
  end

  def html do
    quote do
      use Phoenix.Component
      import Phoenix.Controller, only: [get_csrf_token: 0]
      import Phoenix.HTML
      import Atelier.Components.Core
      alias Phoenix.LiveView.JS
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
```

---

## Part 7: Verified Routes & Link Generation

### 7.1 — The Challenge

The current app uses `~p"/some/path"` for all links. In an embedded library, paths are relative to wherever the host mounts Atelier (e.g., `/dev/atelier/some/path`).

### 7.2 — Solution: Use `live_session` Path Prefix

The `phoenix_live_dashboard` solves this with `__live_dashboard_prefix__()`. We do the same:

```elixir
# In the router macro
unless Module.get_attribute(__MODULE__, :atelier_prefix) do
  @atelier_prefix Phoenix.Router.scoped_path(__MODULE__, path)
                  |> String.replace_suffix("/", "")
  def __atelier_prefix__, do: @atelier_prefix
end
```

Then in the LiveView, use `@atelier_mount_path` assign to build all links:

```elixir
# In AtelierLive mount
def mount(_params, session, socket) do
  prefix = socket.router.__atelier_prefix__()
  {:ok, assign(socket, :atelier_mount_path, prefix)}
end
```

In templates, links use the prefix:

```heex
<!-- Instead of: -->
<.link navigate={~p"/#{file.name}"}>

<!-- Use: -->
<.link navigate={"#{@atelier_mount_path}/#{file.name}"}>
```

---

## Part 8: What Gets Removed

These standalone app concerns are removed entirely:

1. **`lib/atelier/application.ex`** — No OTP supervision tree
2. **`lib/atelier/repo.ex`** — No database
3. **`lib/atelier/mailer.ex`** — No email
4. **`lib/atelier_web/endpoint.ex`** — Use host's endpoint
5. **`lib/atelier_web/telemetry.ex`** — Use host's telemetry
6. **`lib/atelier_web/gettext.ex`** — Use host's gettext (or just hardcode English strings)
7. **`config/`** — All config files (library users configure in their own config)
8. **`priv/`** — No migrations, no static assets (assets served from `dist/`)
9. **`assets/css/`** — No CSS pipeline (CDN only)
10. **`test/`** — Restructure for library tests (no Phoenix test helpers that assume endpoint)

---

## Part 9: Component File System (Host Integration)

### 9.1 — Components Directory

The `Atelier.ComponentsManager` works with the HOST app's file system. The directory and module prefix are derived from the `web_module` config:

```elixir
defmodule Atelier.ComponentsManager do
  def components_dir do
    Atelier.components_dir()
  end

  def module_prefix do
    Atelier.components_module_prefix()
  end

  def list do
    dir = components_dir()
    File.mkdir_p!(dir)
    # ... same tree logic, using configured dir
  end

  def write(%{name: name} = attrs) do
    # Module name uses configured prefix (e.g., MyAppWeb.Components.Button)
    module_name = "#{inspect(module_prefix())}.#{Macro.camelize(stem)}"
    # Write to configured directory (e.g., lib/my_app_web/components/atelier/button.ex)
    path = Path.join(components_dir(), name)
    # ...
  end
end
```

### 9.2 — Template Generation

The component template uses the host's module prefix derived from `web_module`:

```elixir
# With config: web_module: MyAppWeb
# Generates: "MyAppWeb.Components." <> Macro.camelize(stem)
```

Generated components use plain `Phoenix.Component` (not a host-specific macro):

```elixir
# Generated component written to lib/my_app_web/components/atelier/button.ex
defmodule MyAppWeb.Components.Button do
  use Phoenix.Component
  # ... component code
end
```

Since these files live in the host's filetree:
- The host's Tailwind scans them automatically (classes are picked up)
- The host's live reload watches them (changes trigger recompilation)
- The host's colocated hook discovery sees them (if hooks are used in components)

---

## Part 10: Static Assets (Logo, Images)

### 10.1 — Current Usage

- `logo.svg` — referenced in layouts via `~p"/images/logo.svg"`
- `favicon.ico` — in root layout

### 10.2 — Solution

Embed images as inline SVG or data URIs in the templates. For the logo, we can inline the SVG directly. For favicon, either skip it or use a data URI.

Alternatively, the logo/icon can be served through the same `Assets` plug pattern.

---

## Part 11: Implementation Order

### Phase 1: Scaffold Library Structure
1. Strip `mix.exs` down to library deps (remove Ecto, Swoosh, Bandit, etc.)
2. Remove standalone app modules (Application, Repo, Mailer, Endpoint, Telemetry, Gettext)
3. Create `Atelier` config module with `web_module`, `components_dir`, etc.
4. Create `Atelier.Web` internal helpers module (replaces `AtelierWeb`)
5. Move/rename all modules into `Atelier.*` namespace

### Phase 2: Router & Layout
6. Create `Atelier.Router` macro (`atelier/2`)
7. Create `Atelier.LayoutView` + `root.html.heex` (self-contained HTML shell)
8. Create `Atelier.Assets` plug for JS serving
9. Build embedded JS bundle (LiveSocket setup, topbar)
10. Replace all `~p` verified routes with string paths using mount prefix
11. Test: mount Atelier at `/atelier` in a test Phoenix app, verify it renders

### Phase 3: Hooks & Interactivity
12. Test colocated hooks (`.PasteUpload`, `.FormHistory`) in embedded context
13. If build-time colocated hooks don't work from deps, switch to `runtime` variant
14. Verify paste upload, form history, all interactive features work
15. Test: full interactive workflow renders and responds to events

### Phase 4: Configuration & File System
16. Adapt `ComponentsManager` to use `web_module`-derived paths
17. Adapt `AI.Client` to use configured API key
18. Update component template (`template.ex.eex`) to use configured module prefix
19. Update component template to use `use Phoenix.Component` instead of `use AtelierWeb, :live_component`
20. Test: can create/edit/save components in host app's filetree

### Phase 5: Polish & Package
21. Inline static assets (logo SVG, favicon) or serve via Assets plug
22. Set up esbuild config for building `dist/js/app.js`
23. Clean up any remaining references to standalone app
24. Create a demo/example host app for testing
25. Verify hex package includes all needed files (`lib/`, `dist/`, `mix.exs`)

---

## Resolved Questions

1. **Tailwind class scanning** — RESOLVED. Atelier writes component files into the host app's filetree. The host's Tailwind scans those files automatically. Atelier's own UI uses CDN Tailwind (browser build), which processes classes at runtime — no scanning needed.

2. **Heroicons** — RESOLVED. Keep `heroicons` as a library dependency. It's included in all modern LiveView releases we target, so host apps already have it. No extra work needed.

3. **File watching/live reload** — RESOLVED. Since components are written to the host's filetree, the host's `phoenix_live_reload` picks up changes automatically.

4. **`use AtelierWeb, :live_component`** — RESOLVED. Generated components will use `use Phoenix.Component` (or `use Phoenix.LiveComponent`). The template will be updated to not reference any `AtelierWeb` module. The module name prefix comes from the `web_module` config.

5. **Verified routes (`~p`)** — RESOLVED. Remove `~p` sigil usage in Atelier's own templates. Replace with plain string paths using the mount prefix. This is straightforward — just string interpolation instead of the sigil.

6. **Component preview iframes** — RESOLVED. Preview iframes use absolute CDN URLs for CSS, which continue to work regardless of where Atelier is mounted.

7. **Standalone mode** — DEFERRED. Not a requirement for the initial library conversion. Can be added later via a `dev.exs` pattern (similar to how LiveDashboard's repo has one). Useful for developing Atelier itself.

## Remaining Open Questions

1. **Colocated hooks from deps** — Need to test whether `phoenix-colocated` discovers hooks from templates in `deps/atelier/`. If not, use `runtime` colocated hooks as fallback. Test this early in Phase 1.

2. **LiveSocket in embedded root layout** — The embedded root layout creates its own `<html>` document with its own JS (including a new `LiveSocket`). This is the exact same pattern as LiveDashboard, so it should work. But need to verify that the host app's LiveSocket doesn't interfere (they shouldn't — separate HTML documents mean separate JS contexts).
