defmodule Faktory.Supervisor.Workers do
  use Supervisor

  def start_link(_arg) do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(nil) do
    config_module = Faktory.worker_config_module
    config = config_module.all

    children = Enum.map 1..config.concurrency, fn i ->
      Supervisor.child_spec(
        {Faktory.Manager, config},
        id: {Faktory.Worker, config_module, i}
      )
    end

    children = [{Faktory.Heartbeat, config.wid} | children]

    Supervisor.init(children, strategy: :one_for_one)
  end

end
