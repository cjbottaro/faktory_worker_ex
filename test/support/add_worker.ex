defmodule AddWorker do
  use Faktory.Job

  def perform(pid, x, y) do
    PidMap.get(pid) |> send({:add_result, x+y})
  end
end
