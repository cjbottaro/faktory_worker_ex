defmodule Faktory.Supervisor do
  use Supervisor

  @moduledoc false

  def start_link(worker_module) do
    config = Map.new(worker_module.config)
    Supervisor.start_link(__MODULE__, config)
  end

  def init(config) do
    heartbeat = {Faktory.Heartbeat, config}
    fetcher = {Faktory.Stage.Fetcher, config}
    # reporter = {Faktory.Reporter, config}
    tracker = {Faktory.Tracker, config}

    workers = Enum.map 1..config.concurrency, fn index ->
      {Faktory.Stage.Worker, {config, index}}
    end

    # Shutdown order is very important.
    # Reporter need to shutdown last since they need to fail any in-flight jobs.
    [heartbeat, tracker, workers, fetcher]
    |> List.flatten()
    |> Supervisor.init(strategy: :one_for_one)
  end

end
