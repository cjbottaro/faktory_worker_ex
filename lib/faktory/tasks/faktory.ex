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

    if args != [] do
      Mix.shell().error("mix faktory does not take any arguments")
      System.halt(1)
    end

    if not iex_running?() do
      Mix.Task.run("run", ["--no-halt"])
    end
  end

  defp iex_running? do
    Code.ensure_loaded?(IEx) and IEx.started?()
  end

end
