defmodule DieJob do
  use Faktory.Job

  def perform(die) do
    case die do
      "kill" -> Process.exit(self(), :kill)
      "spawn_exception" ->
        # Cause an UndefinedFunctionError exception in a linked process.
        Task.start_link(fn -> raise UndefinedFunctionError end)
        :timer.sleep(:infinity)
      "spawn_kill" ->
        # Cause brutal kill in a linked process.
        Task.start_link(fn -> Process.exit(self(), :kill) end)
        :timer.sleep(:infinity)
    end
  end
end
