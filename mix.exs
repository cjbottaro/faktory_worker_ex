defmodule Faktory.Mixfile do
  use Mix.Project

  def project do
    [
      app: :faktory_worker_ex,
      version: "0.3.0",
      elixir: "~> 1.5",
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env),

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
          "Architecture.md": [title: "Architecture"],
        ]
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
    ]
  end

  defp elixirc_paths(:test) do
    ["lib", "test/support"]
  end

  defp elixirc_paths(_) do
    ["lib"]
  end
end
