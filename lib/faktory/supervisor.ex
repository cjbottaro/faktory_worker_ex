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

    name = Faktory.Registry.name(config.module, :job_queue)
    job_queue = %{
      id: {config.module, :job_queue},
      start: {BlockingQueue, :start_link, [config.concurrency, [name: name]]}
    }

    name = Faktory.Registry.name(config.module, :report_queue)
    report_queue = %{
      id: {config.module, :report_queue},
      start: {BlockingQueue, :start_link, [config.concurrency * 3, [name: name]]}
    }

    # TODO make the count configurable
    producers = Enum.map 1..1, fn index ->
      %{
        id: {config.module, Faktory.Producer, index},
        start: {Faktory.Producer, :start_link, [config]}
      }
    end

    consumers = Enum.map 1..config.concurrency, fn index ->
      %{
        id: {config.module, Faktory.Consumer, index},
        start: {Faktory.Consumer, :start_link, [config]}
      }
    end

    # TODO make the count configurable
    reporters = Enum.map 1..1, fn index ->
      %{
        id: {config.module, Faktory.Reporter, index},
        start: {Faktory.Reporter, :start_link, [config]}
      }
    end

    children = [
      heartbeat,
      job_queue,
      report_queue
      | producers ++ consumers ++ reporters
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

end
