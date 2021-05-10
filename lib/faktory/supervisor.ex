defmodule Faktory.Supervisor do
  use Supervisor

  @moduledoc false

  def start_link(worker_module) do
    config = Map.new(worker_module.config)
    Supervisor.start_link(__MODULE__, config)
  end

  def init(config) do
    if start?(config) do
      [
        {Faktory.Manager, config},
        {Faktory.Stage.Fetcher, config},
        {Faktory.Stage.Worker, config}
      ]
    else
      []
    end
    |> Supervisor.init(strategy: :one_for_one)
  end

  defp start?(config) do
    if Map.has_key?(config, :start) do
      config.start
    else
      Faktory.start_workers?
    end
  end

end
