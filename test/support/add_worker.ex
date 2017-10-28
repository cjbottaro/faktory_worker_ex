defmodule AddWorker do
  use Faktory.Job

  def perform(pid, x, y) do
    Stack.push(x+y)
    PidMap.get(pid) |> send(:done)
  end
end
