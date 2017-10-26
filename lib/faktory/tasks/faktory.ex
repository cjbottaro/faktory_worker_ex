defmodule Mix.Tasks.Faktory do
  use Mix.Task
  require Logger

  @shortdoc "Start Faktory worker"

  def run(args) do
    IO.inspect args

    # Signify that we want to start the workers.
    Faktory.put_env(:start_workers, true)

    # Easy enough.
    Mix.Task.run "app.start"

    shh_just_go_to_sleep()
  end

  defp shh_just_go_to_sleep do
    receive do
      something ->
        Logger.warn("!!! Uh oh, main process received a message: #{inspect(something)}")
    end
    shh_just_go_to_sleep()
  end

end
