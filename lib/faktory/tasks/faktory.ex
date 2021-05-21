defmodule Mix.Tasks.Faktory do
  @shortdoc "Start Faktory workers"

  @moduledoc """
  Startup all configured Faktory workers.

  ```sh
  mix faktory
  ```

  Any `Faktory.Worker` with configuration `:start` equal to `nil` or `true` will be started.
  """

  use Mix.Task

  @doc false
  def run(args) do
    Application.put_env(:faktory_worker_ex, :start_workers, true)
    Mix.Tasks.Run.run run_args() ++ args
  end

  defp run_args do
    if iex_running?(), do: [], else: ["--no-halt"]
  end

  defp iex_running? do
    Code.ensure_loaded?(IEx) and IEx.started?()
  end

end
