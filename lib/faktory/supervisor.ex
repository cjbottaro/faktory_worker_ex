defmodule Faktory.Supervisor do
  use Supervisor

  @moduledoc false

  def start_link(worker_module) do
    config = Map.new(worker_module.config)
    Supervisor.start_link(__MODULE__, config)
  end

  def init(config) do
    [
      {Faktory.Heartbeat, config},
      {Faktory.Tracker, config},
      {Faktory.Stage.Fetcher, config},
      {Faktory.Stage.Worker, config}
    ]
    |> Supervisor.init(strategy: :one_for_one)
  end

end
