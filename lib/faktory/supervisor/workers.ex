defmodule Faktory.Supervisor.Workers do
  @moduledoc false
  use Supervisor

  import Faktory.Utils, only: [to_int: 1]

  def start_link(config) do
    name = {:global, {__MODULE__, config.name}}
    Supervisor.start_link(__MODULE__, config, name: name)
  end

  def init(config) do

    # Worker processes
    children = Enum.map 1..to_int(config.concurrency), fn i ->
      Supervisor.child_spec(
        {Faktory.Worker, config},
        id: {Faktory.Worker, config.name, i}
      )
    end

    # Add poolboy process and heartbeat process.
    children = [
      pool_spec(config),
      {Faktory.Heartbeat, config}
      | children
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp pool_spec(config) do
    pool_options = [
      name: {:local, config.name},
      worker_module: Faktory.Connection,
      size: to_int(config.pool),
      max_overflow: 0
    ]
    :poolboy.child_spec(config.name, pool_options, config)
  end
end
