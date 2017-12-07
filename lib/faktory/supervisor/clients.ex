defmodule Faktory.Supervisor.Clients do
  @moduledoc false
  use Supervisor

  import Faktory.Utils, only: [to_int: 1]

  def start_link(config) do
    Supervisor.start_link(__MODULE__, config, name: __MODULE__)
  end

  def init(config) do
    Supervisor.init(children(config), strategy: :one_for_one)
  end

  def children(nil), do: []

  def children(config) do
    pool_options = [
      name: {:local, config.name},
      worker_module: Faktory.Connection,
      size: to_int(config.pool),
      max_overflow: 2
    ]

    [:poolboy.child_spec(config.name, pool_options, config)]
  end
end
