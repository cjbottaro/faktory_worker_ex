defmodule Faktory.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(nil) do
    Supervisor.init([
      Faktory.Supervisor.Clients,
      Faktory.Supervisor.Workers,
    ], strategy: :one_for_one)
  end

end
