defmodule SimpleApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :simple_app,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {SimpleApp.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:igniter, "~> 0.5"},
      {:oban_pro, "~> 1.5", repo: "oban"},
      {:ecto, "~> 3.12"},
      {:ecto_sql, "~> 3.12"},
      {:postgrex, "~> 0.18"},
      {:oban_web, "~> 2.11"},
      {:langchain, "~> 0.3"},
      {:styler, "~> 1.2", only: [:dev, :test], runtime: false},
      {:req, "~> 0.5"}
    ]
  end
end
