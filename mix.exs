defmodule Faktory.Mixfile do
  use Mix.Project

  @version "1.0.0"

  def project do
    [
      app: :faktory_worker_ex,
      version: @version,
      elixir: ">= 1.5.0",
      start_permanent: Mix.env == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env),
      aliases: aliases(),

      # Hex
      description: "Elixir worker for Faktory (successor of Sidekiq); async/background queue processing",
      package: [
        maintainers: ["Christopher J. Bottaro"],
        licenses: ["GNU General Public License v3.0"],
        links: %{"GitHub" => "https://github.com/cjbottaro/faktory_worker_ex"},
      ],

      # Docs
      docs: [
        extras: [
          "README.md": [title: "README"],
          "CHANGELOG.md": [title: "CHANGELOG"],
        ],
        main: "README",
        groups_for_modules: [
          "Logging": [~r/Faktory\.Logger\.\w+/],
        ],
      ],

      xref: [exclude: IEx]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto, :ssl],
      mod: {Faktory.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:connection, "~> 1.0"},
      {:jason, "~> 1.1"},
      {:gen_stage, "~> 1.0"},
      {:nimble_pool, "~> 0.0"},
      {:telemetry, "~> 0.4 or ~> 1.0"},
      {:ex_doc, "~> 0.19", only: :dev},
    ]
  end

  defp elixirc_paths(:test) do
    ["lib", "test/support"]
  end

  defp elixirc_paths(:dev) do
    ["lib", "dev"]
  end

  defp elixirc_paths(_) do
    ["lib"]
  end

  defp aliases do
    [
      compile: ["compile --warnings-as-errors"]
    ]
  end
end
