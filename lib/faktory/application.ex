defmodule Faktory.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    :ok = Faktory.Logger.Socket.init()
    :ok = Faktory.Logger.Connection.init()
    :ok = Faktory.Logger.Command.init()
    :ok = Faktory.Logger.Job.init()

    children = [
      Faktory.Client.Default
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
