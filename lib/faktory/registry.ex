defmodule Faktory.Registry do
  @moduledoc false

  def child_spec(_args) do
    %{
      id: __MODULE__,
      start: {Registry, :start_link, [[keys: :unique, name: __MODULE__]]}
    }
  end

  def name(id) do
    {:via, Registry, {__MODULE__, id}}
  end
end
