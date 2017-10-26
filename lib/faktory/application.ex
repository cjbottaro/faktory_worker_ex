defmodule Faktory.Application do
  use Application

  def start(_type, _args) do
    Faktory.Supervisor.start_link
  end
end
