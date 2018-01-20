defmodule Faktory.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(nil) do
    alias Faktory.Configuration

    clients = Configuration.modules(:client)
    workers = Configuration.modules(:worker)

    children = if Faktory.start_workers? do
      [
        {Faktory.Supervisor.Clients, clients},
        {Faktory.Supervisor.Workers, workers}
      ]
    else
      [
        {Faktory.Supervisor.Clients, clients},
      ]
    end

    Supervisor.init(children, strategy: :one_for_one)
  end

end
