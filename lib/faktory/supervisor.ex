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
    tracker = {Faktory.Tracker, config}

    workers = Enum.map 1..config.concurrency, fn index ->
      {Faktory.Stage.Worker, {config, index}}
    end

    # Shutdown order is very important.
    # Fetcher needs to shutdown first (brutal kill is fine) so no more jobs get
    # plucked from the queue while we're shutting down. The Tracker needs to
    # shutdown last(ish) so it can fail any jobs didn't complete in the shutdown
    # grace period.
    [heartbeat, tracker, workers, fetcher]
    |> List.flatten()
    |> Supervisor.init(strategy: :one_for_one)
  end

end
