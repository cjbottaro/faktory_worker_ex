defmodule Faktory.Supervisor.Workers do
  @moduledoc false
  use Supervisor
  require Faktory.Logger

  def start_link(config_modules) do
    Supervisor.start_link(__MODULE__, config_modules, name: __MODULE__)
  end

  def init([]), do: Supervisor.init([], strategy: :one_for_one)

  def init(config_modules) do
    children(config_modules) |>
      Supervisor.init(strategy: :one_for_one)
  end

  def children(config_modules) do
    Enum.flat_map(config_modules, fn module ->
      config = module.config

      # It is really important that the Poolboy workers start before the actual
      # workers otherwise the workers will try to checkout connections before
      # the pools are ready. Consider rearranging the supervisor tree.

      [
        pool_spec(config),
        Supervisor.child_spec({Faktory.Heartbeat, config}, id: {module, :heartbeat})
      ]
      ++
      Enum.map(1..config.concurrency, fn i ->
        Supervisor.child_spec({Faktory.Worker, config}, id: {module, i})
      end)

    end) |> IO.inspect
  end

  defp pool_spec(config) do
    pool_options = [
      name: {:local, config.module},
      worker_module: Faktory.Connection,
      size: config.pool,
      max_overflow: 0
    ]
    :poolboy.child_spec(config.module, pool_options, config)
  end

end
