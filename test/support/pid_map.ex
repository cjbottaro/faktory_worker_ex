defmodule PidMap do

  def start_link do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def register(pid \\ nil) do
    pid = pid || self()
    key = inspect(pid)
    Agent.update(__MODULE__, &Map.put(&1, key, pid))
    key
  end

  def get(key) do
    Agent.get(__MODULE__, &Map.get(&1, key))
  end

  def items do
    Agent.get(__MODULE__, & &1)
  end

end
