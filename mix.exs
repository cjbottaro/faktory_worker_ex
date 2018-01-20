defmodule Faktory.Mixfile do
  use Mix.Project

  @version "0.5.0"

  def project do
    [
      app: :faktory_worker_ex,
      version: @version,
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env),
      aliases: aliases(),

      # Hex
      description: "Elixir worker for Faktory",
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
          "Architecture.md": [title: "Architecture"],
        ],
        main: "README",
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Faktory.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:connection, "~> 1.0"},
      {:poison, "~> 3.1"},
      {:poolboy, "~> 1.5"},
      {:ex_doc, "~> 0.18.1", only: :dev},
      {:certifi, "~> 2.0"}
    ]
  end

  defp elixirc_paths(:test) do
    ["lib", "test/support"]
  end

  defp elixirc_paths(_) do
    ["lib"]
  end

  defp aliases do
    [
      "compile": ["compile --warnings-as-errors"]
    ]
  end
end
