defmodule Faktory.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    :ets.new(Faktory.Configuration, [:set, :public, :named_table])
    Faktory.Supervisor.start_link
  end
end
