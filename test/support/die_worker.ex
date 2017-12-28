defmodule DieWorker do
  use Faktory.Job

  def perform(die) do
    if die do
      Process.exit(self(), :kill)
    else
      "Didn't die!"
    end
  end
end
