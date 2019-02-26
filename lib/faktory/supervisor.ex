defmodule Faktory.Supervisor do
  use Supervisor

  @moduledoc false

  def start_link(worker_module) do
    config = Map.new(worker_module.config)
    Supervisor.start_link(__MODULE__, config)
  end

  def init(config) do
    heartbeat = %{
      id: {config.module, :heartbeat},
      start: {Faktory.Heartbeat, :start_link, [config]}
    }

    # TODO make the count configurable
    fetchers = Enum.map 1..config.fetcher_count, fn index ->
      %{
        id: {config.module, Faktory.Fetcher, index},
        start: {Faktory.Fetcher, :start_link, [config, index]}
      }
    end

    job_workers = Enum.map 1..config.concurrency, fn index ->
      %{
        id: {config.module, Faktory.Runner, index},
        start: {Faktory.Runner, :start_link, [config, index]}
      }
    end

    # TODO make the count configurable
    reporters = Enum.map 1..config.reporter_count, fn index ->
      %{
        id: {config.module, Faktory.Reporter, index},
        start: {Faktory.Reporter, :start_link, [config, index]}
      }
    end

    children = [heartbeat | fetchers ++ job_workers ++ reporters]
    Supervisor.init(children, strategy: :one_for_one)
  end

end
