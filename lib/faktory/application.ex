defmodule Faktory.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    :ok = Faktory.Logger.init()

    children = [Faktory.Registry]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
