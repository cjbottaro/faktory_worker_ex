defmodule Faktory.Supervisor.Workers do
  use Supervisor

  def start_link(_arg) do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(nil) do
    Supervisor.init([
    ], strategy: :one_for_one)
  end

end
