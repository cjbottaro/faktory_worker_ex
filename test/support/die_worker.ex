defmodule DieWorker do
  use Faktory.Job

  def perform(die) do
    case die do
      "kill" -> Process.exit(self(), :kill)
      "spawn" ->
        # Cause an UndefinedFunctionError exception in a linked process.
        Task.start_link(fn -> Factory.some_funky_function end)
        :timer.sleep(:infinity)
    end
  end
end
