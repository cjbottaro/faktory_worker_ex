defmodule Faktory.Supervisor.Workers do
  @moduledoc false
  use Supervisor

  def start_link(_arg \\ nil) do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(nil) do
    config_module = Faktory.worker_config_module
    config = config_module.all

    # Manager processes
    children = Enum.map 1..config.concurrency, fn i ->
      Supervisor.child_spec(
        {Faktory.Manager, config},
        id: {Faktory.Worker, config_module, i}
      )
    end

    # Add poolboy process and heartbeat process.
    children = [
      pool_spec(config_module, config),
      {Faktory.Heartbeat, config.wid}
      | children
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp pool_spec(config_module, config) do
    pool_options = [
      name: {:local, config_module},
      worker_module: Faktory.Connection,
      size: config.pool,
      max_overflow: 2
    ]
    :poolboy.child_spec(config_module, pool_options, config)
  end

end
