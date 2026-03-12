defmodule Atelier do
  @moduledoc """
  Atelier - Interactive component builder for Phoenix LiveView.

  ## Configuration

      # config/dev.exs
      config :atelier,
        anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
        web_module: MyAppWeb

  ## Options

    * `:anthropic_api_key` - Required. Your Anthropic API key for AI features.

    * `:web_module` - Required. Your Phoenix web module (e.g., `MyAppWeb`).
      Used to derive the components directory and module prefix.

    * `:components_dir` - Optional. Directory where components are stored.
      Defaults to `lib/<web_module_snake>/components/atelier/`.

    * `:model` - Optional. Default AI model. Defaults to `"claude-sonnet-4-6"`.
  """

  def anthropic_api_key do
    Application.get_env(:atelier, :anthropic_api_key) ||
      raise "Missing :anthropic_api_key config for :atelier"
  end

  def web_module do
    Application.get_env(:atelier, :web_module) ||
      raise """
      Missing :web_module config for :atelier.

      Add to your config:

          config :atelier,
            web_module: MyAppWeb
      """
  end

  def components_dir do
    Application.get_env(:atelier, :components_dir) || default_components_dir()
  end

  def components_module_prefix do
    Module.concat(web_module(), "Components")
  end

  defp default_components_dir do
    web_snake =
      web_module()
      |> Module.split()
      |> Enum.join(".")
      |> Macro.underscore()

    Path.join(File.cwd!(), "lib/#{web_snake}/components/atelier")
  end
end
