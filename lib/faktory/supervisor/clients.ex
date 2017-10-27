defmodule Faktory.Supervisor.Clients do
  @moduledoc false
  use Supervisor

  def start_link(_arg) do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(nil) do
    Supervisor.init(children(), strategy: :one_for_one)
  end

  def children do
    children(Faktory.client_config_module)
  end

  def children(nil), do: []

  def children(config_module) do
    config = config_module.all

    pool_options = [
      name: {:local, config_module},
      worker_module: Faktory.Connection,
      size: config.pool,
      max_overflow: 2
    ]

    [:poolboy.child_spec(config_module, pool_options, config)]
  end

end
