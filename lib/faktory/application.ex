defmodule Faktory.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    Agent.start_link(fn -> nil end)
  end
end
