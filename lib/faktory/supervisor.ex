defmodule Faktory.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(nil) do

    # Only start the workers from the mix task.
    children = if Faktory.start_workers? do
      [Faktory.Supervisor.Workers]
    else
      []
    end

    # Always start the clients supervisor.
    children = [Faktory.Supervisor.Clients | children]

    Supervisor.init(children, strategy: :one_for_one)
  end

end
