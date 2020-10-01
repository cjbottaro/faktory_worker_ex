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

  @shortdoc "Start Faktory worker"

  @doc false
  def run(args) do
    OptionParser.parse(args,
      strict: [concurrency: :integer, queues: :string, pool: :integer, tls: :boolean],
      aliases: [c: :concurrency, q: :queues, p: :pool, t: :tls]
    ) |> case do
      {options, [], args} -> start(options, args)
      _ ->
        print_usage()
        exit(:normal)
    end
  end

  defp start(options, args) do
    # Signify that we want to start the workers.
    Faktory.put_env(:start_workers, true)

    # Store our cli options.
    Faktory.put_env(:cli_options, options)

    Mix.Tasks.Run.run run_args() ++ args
  end

  defp print_usage do
    IO.puts """
    mix faktory [options]

    -c, --concurrency  Number of worker processes
    -q, --queues       Space seperated list of queues
    -t, --tls          Enable TLS when connecting to Faktory server. Default: disable TLS
    """
  end

  defp run_args do
    if iex_running?(), do: [], else: ["--no-halt"]
  end

  defp iex_running? do
    Code.ensure_loaded?(IEx) and IEx.started?()
  end

end
