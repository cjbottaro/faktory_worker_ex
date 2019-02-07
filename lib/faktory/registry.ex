defmodule Faktory.Registry do

  def child_spec(_args) do
    %{
      id: __MODULE__,
      start: {Registry, :start_link, [[keys: :unique, name: __MODULE__]]}
    }
  end

  def name(worker_module, name) do
    {:via, Registry, {__MODULE__, {worker_module, name}}}
  end
end
