defmodule Faktory.Supervisor.Workers do
  @moduledoc false
  use Supervisor

  def start_link(config_module) do
    Supervisor.start_link(__MODULE__, config_module, name: {:global, {__MODULE__, config_module}})
  end

  def init(config_module) do
    config = config_module.all

    # Worker processes
    children = Enum.map 1..config.concurrency, fn i ->
      Supervisor.child_spec(
        {Faktory.Worker, config},
        id: {Faktory.Worker, config_module, i}
      )
    end

    # Add poolboy process and heartbeat process.
    children = [
      pool_spec(config_module, config),
      {Faktory.Heartbeat, config}
      | children
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp pool_spec(config_module, config) do
    pool_options = [
      name: {:local, config_module},
      worker_module: Faktory.Connection,
      size: config.pool,
      max_overflow: 0
    ]
    :poolboy.child_spec(config_module, pool_options, config)
  end

end
