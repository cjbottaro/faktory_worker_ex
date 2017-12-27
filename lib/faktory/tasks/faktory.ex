defmodule Mix.Tasks.Faktory do
  @moduledoc """
  Use this to start up the worker and start shreddin through your work!

  ```
  mix faktory
  ```

  Run `mix factory -h` for usage information.

  Command line arguments will override configuration defined in modules.

  Command line arguments only affect worker configuration (not client configuration).
  """

  use Mix.Task
  alias Faktory.Logger

  @shortdoc "Start Faktory worker"

  @doc false
  def run(args) do
    OptionParser.parse(args,
      strict: [concurrency: :integer, queues: :string, pool: :integer, use_tls: :boolean],
      aliases: [c: :concurrency, q: :queues, p: :pool, t: :use_tls, tls: :use_tls]
    ) |> case do
      {options, [], []} -> start(options)
      _ ->
        print_usage()
        exit(:normal)
    end
  end

  defp start(options) do
    # Signify that we want to start the workers.
    Faktory.put_env(:start_workers, true)

    # Store our cli options.
    Faktory.put_env(:cli_options, options)

    # Easy enough.
    Mix.Task.run "app.start"

    shh_just_go_to_sleep()
  end

  defp print_usage do
    IO.puts """
    mix faktory [options]

    -c, --concurrency  Number of worker processes
    -q, --queues       Comma seperated list of queues
    -p, --pool         Connection pool size. Default: <concurrency>
    -t, --tls          Enable TLS when connecting to Faktory server. Default: disable TLS
    """
  end

  defp shh_just_go_to_sleep do
    receive do
      something ->
        Logger.warn("!!! Uh oh, main process received a message: #{inspect(something)}")
    end
    shh_just_go_to_sleep()
  end

end
