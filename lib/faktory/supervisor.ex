defmodule Faktory.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(nil) do
    alias Faktory.Configuration

    # Only start the workers from the mix task.
    children = if Faktory.start_workers? do
      [{Faktory.Supervisor.Workers, Configuration.fetch(:worker)}]
    else
      []
    end

    # Always start the clients supervisor.
    children = [
      {Faktory.Supervisor.Clients, Configuration.fetch(:client)}
      | children
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

end
