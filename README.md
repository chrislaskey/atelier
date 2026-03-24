# Atelier

### Installation

Add `atlier` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:atelier, git: "https://github.com/chrislaskey/atelier", branch: "main"},
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

### Setup

#### 1. Update config

Add to `config/runtime.exs`:

```elixir
# config/runtime.exs
config :atelier,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  web_module: MyAppWeb
```

Note: By default components are written to `lib/my_app_web/components/atelier/*` directory.
This can be configured to a different path using the `components_dir:` option in
the runtime.exs config.

#### 2. Add routes

Add the Atelier route to your router:

```elixir
# lib/my_app_web/router.ex
import Atelier.Router

scope "/" do
  pipe_through :browser
  atelier "/atelier"
end
```

Visit `/atelier` in your browser to see the Atelier interface.
