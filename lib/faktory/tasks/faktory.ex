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
    {faktory_args, run_args} = Enum.split_while(args, & &1 != "--")

    # Ditch the "--" from run_args if there are any run_args.
    run_args = case run_args do
      ["--" | run_args] -> run_args
      run_args -> run_args
    end

    OptionParser.parse(faktory_args,
      strict: [concurrency: :integer, queues: :string, pool: :integer, tls: :boolean, no_start: :boolean],
      aliases: [c: :concurrency, q: :queues, p: :pool, t: :tls]
    ) |> case do
      {options, [], []} -> start(options, run_args)
      _ ->
        print_usage()
        exit(:normal)
    end
  end

  defp start(options, run_args) do
    # Signify that we want to start the workers.
    Faktory.put_env(:start_workers, true)

    # Store our cli options.
    Faktory.put_env(:cli_options, options)

    Mix.Tasks.Run.run run_args ++ no_start_arg(options) ++ no_halt_arg()
  end

  defp print_usage do
    IO.puts """
    mix faktory [options]

    -c, --concurrency  Number of worker processes
    -q, --queues       Space seperated list of queues
    -t, --tls          Enable TLS when connecting to Faktory server. Default: disable TLS
    --no-start         Do not start applications after compilation (like mix run --no-start)
    """
  end

  defp no_start_arg(options) do
    if options[:no_start] do
      ["--no-start"]
    else
      []
    end
  end

  defp no_halt_arg do
    if iex_running?(), do: [], else: ["--no-halt"]
  end

  defp iex_running? do
    Code.ensure_loaded?(IEx) and IEx.started?()
  end

end
