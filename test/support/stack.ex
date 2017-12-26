defmodule Stack do

  def start_link do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  def push(item) do
    Agent.update(__MODULE__, &[item | &1])
  end

  def pop do
    Agent.get_and_update(__MODULE__, fn [item | list] -> {item, list} end)
  end

  def items do
    Agent.get(__MODULE__, & &1)
  end

  def clear do
    Agent.update(__MODULE__, fn _ -> [] end)
  end

end
