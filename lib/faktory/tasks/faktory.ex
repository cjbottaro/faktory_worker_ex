defmodule Mix.Tasks.Faktory do
  @shortdoc "Start Faktory workers"

  @moduledoc """
  Startup all configured Faktory workers.

  ## Command line options

  * `--only, -o` Only startup specified workers.
  * `--except, -e` Startup all except specified workers.

  ## Examples
  ```sh
  mix faktory

  mix faktory -o FooWorker
  mix faktory -e BarWorker

  mix faktory --only FooWorker,BarWorker
  mix faktory -o FooWorker -o BarWorker

  mix faktory --except FooWorker,BarWorker
  mix faktory -e FooWorker -e BarWorker
  ```
  """

  use Mix.Task

  @switches [
    only: :keep,
    except: :keep,
  ]

  @aliases [
    o: :only,
    e: :except,
  ]

  @defaults [
    only: [],
    except: [],
  ]

  @doc false
  def run(args) do
    Mix.Task.run("app.config")
    {opts, args} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    opts = Keyword.merge(@defaults, opts)

    only = normalize_only_except(opts[:only])
    except = normalize_only_except(opts[:except])

    if only != [] and except != [] do
      Mix.shell().error("--only and --except are mutually exclusive")
      System.halt(1)
    end

    cond do
      only == [] and except == [] ->
        Application.put_env(:faktory_worker_ex, :start_workers, true)

      only != [] ->
        Application.put_env(:faktory_worker_ex, :start_workers, :only)
        Enum.each(only, &start_worker(&1, true))

      except != [] ->
        Application.put_env(:faktory_worker_ex, :start_workers, :except)
        Enum.each(except, &start_worker(&1, false))
    end

    Mix.Tasks.Run.run run_args() ++ args
  end

  defp start_worker(module, bool) do
    app = Application.get_application(module)

    if !app do
      Mix.shell().error("Cannot find application for #{inspect module}")
      System.halt(1)
    end

    env = Application.get_env(app, module, [])
    |> Keyword.update(:start, bool, fn _ -> bool end)

    Application.put_env(app, module, env, persistent: true)
  end

  defp normalize_only_except(items) do
    List.wrap(items)
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&Module.safe_concat([&1]))
  end

  defp run_args do
    if iex_running?(), do: [], else: ["--no-halt"]
  end

  defp iex_running? do
    Code.ensure_loaded?(IEx) and IEx.started?()
  end

end
