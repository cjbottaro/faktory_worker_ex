defmodule Faktory.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    Faktory.Configuration.init
    Faktory.Supervisor.start_link
  end
end
