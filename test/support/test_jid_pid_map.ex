defmodule TestJidPidMap do

  def start_link do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def register(jid) do
    pid = self()
    Agent.update(__MODULE__, &Map.put(&1, jid, pid))
  end

  def get(jid) do
    Agent.get(__MODULE__, & &1[jid])
  end

end
