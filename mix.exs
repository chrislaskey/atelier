defmodule Atelier.MixProject do
  use Mix.Project

  @version "0.2.0"

  def project do
    [
      app: :atelier,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix_live_view, "~> 1.0"},
      {:ecto, "~> 3.12", optional: true},
      {:req, "~> 0.5", optional: true},
      {:jason, "~> 1.2", optional: true},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1,
       optional: true},
    ]
  end

  defp package do
    [
      files: ~w(lib dist mix.exs README.md LICENSE.md)
    ]
  end
end
