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
      strict: [concurrency: :integer, queues: :string, pool: :integer, tls: :boolean],
      aliases: [c: :concurrency, q: :queues, p: :pool, t: :tls]
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

    if ! IEx.started? do
      Process.sleep(:infinity)
    end
  end

  defp print_usage do
    IO.puts """
    mix faktory [options]

    -c, --concurrency  Number of worker processes
    -q, --queues       Space seperated list of queues
    -p, --pool         Connection pool size. Default: <concurrency>
    -t, --tls          Enable TLS when connecting to Faktory server. Default: disable TLS
    """
  end

end
