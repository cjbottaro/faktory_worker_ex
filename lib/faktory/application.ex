defmodule Faktory.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    :ok = Faktory.Logger.Socket.init()
    :ok = Faktory.Logger.Connection.init()
    :ok = Faktory.Logger.Command.init()
    :ok = Faktory.Logger.Job.init()

    Supervisor.start_link([], strategy: :one_for_one)
  end
end
