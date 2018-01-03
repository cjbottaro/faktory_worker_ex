defmodule Faktory.Supervisor.Clients do
  @moduledoc false
  use Supervisor

  def start_link(config_modules) do
    Supervisor.start_link(__MODULE__, config_modules, name: __MODULE__)
  end

  def init(config_modules) do
    children(config_modules) |>
      Supervisor.init(strategy: :one_for_one)
  end

  def children([]), do: []

  def children(config_modules) do
    Enum.map(config_modules, fn module ->
      config = module.config

      pool_options = [
        name: {:local, module},
        worker_module: Faktory.Connection,
        size: config.pool,
        max_overflow: 2
      ]

      :poolboy.child_spec(module, pool_options, config)
    end)
  end

end
