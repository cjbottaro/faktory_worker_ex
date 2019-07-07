defmodule Faktory.Supervisor do
  use Supervisor

  @moduledoc false

  def start_link(worker_module) do
    config = Map.new(worker_module.config)
    Supervisor.start_link(__MODULE__, config)
  end

  def init(config) do
    heartbeat = {Faktory.Heartbeat, config}

    fetchers = Enum.map 1..config.fetcher_count, fn index ->
      {Faktory.Stage.Fetcher, {config, index}}
    end

    runners = Enum.map 1..config.concurrency, fn index ->
      {Faktory.Stage.Worker, {config, index}}
    end

    reporters = Enum.map 1..config.reporter_count, fn index ->
      {Faktory.Stage.Reporter, {config, index}}
    end

    children = [heartbeat | fetchers ++ runners ++ reporters]
    Supervisor.init(children, strategy: :one_for_one)
  end

end
