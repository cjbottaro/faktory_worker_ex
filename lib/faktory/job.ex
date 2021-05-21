defmodule Faktory.Job do
  @moduledoc """
  Use this module to create your job processors.

  ## Getting started

  All that is required is to define a `perform` function that takes zero or more
  arguments.

  ```elixir
  defmodule MyFunkyJob do
    use Faktory.Job

    def perform(arg1, arg2) do
      # ... do something ...
    end
  end

  # To enqueue jobs of this type.
  {:ok, client} = Faktory.Client.start_link()
  MyFunkyJob.perform_async([1, "foo"], client: client)
  ```

  **IMPORTANT**
  > The first argument to `c:perform_async/2` must be a list of
  > size exactly equal to the arity of your `perform` function.

  ## Client

  In order to enqueue a job via `c:perform_async/2`, we need a client connection
  to the Faktory server.

  Consider starting a named `Faktory.Client` (preferably in a supervision tree).
  ```
  {:ok, conn} = Faktory.Client.start_link([host: "foo.bar.com"], name: MyFaktoryClient)
  ```

  Now tell your job to use that client connection.
  ```
  defmodule MyFunkyJob do
    use Faktory.Job, client: MyFaktoryClient

    def perform(n1, n2), do: nil
  end

  MyFunkJob.perform_async([1, 2])
  ```

  See the configuration section below for how to set a global default client.

  ## Configuration

  You can set global configuration that affects all modules via `Config`.
  ```
  config :faktory_worker_ex, Faktory.Job,
    queue: "not-default",
    client: MyFaktoryClient

  defmodule MyFunkyJob do
    use Faktory.Job
  end

  "not-default" = MyFunkyJob.config[:queue]
  MyFaktoryClient = MyFunkyJob.config[:client]
  ```

  You can set job specific configuration at compile time.
  ```
  defmodule MyFunkyJob do
    use Faktory.Job, queue: "funky-queue", client: MyFaktoryClient
  end
  ```

  Or via `Config`, which allows for run time config via `config/runtime.exs`.
  ```
  config :your_application, MyFunkyJob,
    queue: "funky-queue",
    client: MyFaktoryClient
  ```

  Config via `Config` takes precedence over compile time config, and job
  specific config take precedence over the global `Faktory.Job` config. Finally,
  function call arguments take precedence over config. All config and function
  arguments are merged together.
  """

  @defaults [
    queue: "default",
    middleware: [],
    client: Faktory.DefaultClient,
  ]

  @doc """
  Default job configuration.

  ```elixir
  iex(1)> Faktory.Job.defaults()
  #{inspect @defaults, pretty: true, width: 0}
  ```
  """
  def defaults do
    @defaults
  end

  @doc """
  Global job configuration.

  This overrides the `defaults/1` with configuration specified via `Config`.
  ```
  config :faktory_worker_ex, Faktory.Job, queue: "not-default"

  iex(1)> Faktory.Job.defaults()
  #{inspect @defaults, pretty: true, width: 0}

  iex(2)> Faktory.Job.config()
  #{inspect Keyword.merge(@defaults, queue: "not-default"), pretty: true, width: 0}
  ```
  """
  def config do
    config = Application.get_application(__MODULE__)
    |> Application.get_env(__MODULE__, [])

    Keyword.merge(@defaults, config)
  end

  @doc false
  def new(fields)

  def new(fields) when is_list(fields) or is_map(fields) do
    Map.new(fields, fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
    end)
    |> Map.take([
      :jid,
      :jobtype,
      :args,
      :queue,
      :reserve_for,
      :at,
      :retry,
      :backtrace,
      :created_at,
      :enqueued_at,
      :failure,
      :custom
    ])
    |> Map.put_new(:jid, Faktory.Utils.new_jid())
    |> Map.put_new(:args, [])
    |> Map.put_new(:reserve_for, 1800)
  end

  def new(fields) when is_binary(fields) do
    Jason.decode!(fields) |> new()
  end

  defmacro __using__(config \\ []) do
    quote location: :keep do
      @behaviour Faktory.Job
      @config unquote(config)

      def config do
        config = Application.get_application(__MODULE__)
        |> Application.get_env(__MODULE__, [])

        Faktory.Job.config()
        |> Keyword.merge(@config)
        |> Keyword.merge(config)
        |> Keyword.put_new(:jobtype, inspect(__MODULE__))
      end

      def perform_async(args, options \\ []) do
        options = Keyword.merge(config(), options)
        Faktory.Job.perform_async(args, options)
      end

    end
  end

  @doc """
  Specific job configuration.

  Returns the configuration for this specific job taking into consideration
  global configuration, compile time configuration, and run time configuration.
  """
  @callback config() :: Keyword.t

  @doc """
  Enqueue a job.

  `options` can override any configuration in `c:config/0`.
  ```
  job_args = [123, "abc"]
  MyJob.perform_async(job_args)
  MyJob.perform_async(job_args, queue: "not_default" jobtype: "Worker::MyJob")
  ```
  """
  @callback perform_async(args :: [term], options :: Keyword.t) :: {:ok, Faktory.push_job} | {:error, reason :: term}

  @doc false
  def perform_async(args, options) do
    case Keyword.pop(options, :client) do
      {nil, _options} -> {:error, ":client is required"}
      {client, options} ->
        job = Keyword.put(options, :args, args) |> new()
        Faktory.Client.push(client, options, job)
    end
  end

end
