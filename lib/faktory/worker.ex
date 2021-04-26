defmodule Faktory.Worker do
  @moduledoc """
  Create and configure a worker for processing jobs.

  A worker runs in an endless loop, fetching and processing jobs. Fetched jobs
  are dispatched to a corresponding `Faktory.Job` for processing.

  ```elixir
  {:ok, worker} = Faktory.Worker.start_link(concurrency: 5)
  Faktory.Worker.stop(worker)
  ```

  Typically you would want to put the worker in your application's supervision
  tree. Then it can be started with `mix faktory`.

  ## Jobtypes

  If a job is fetched with `{"jobtype": "FooBar", "args": [1]}` then the job
  will be processed with `FooBar.perform/1`, unless a `Faktory.Job` module
  overrides its configured `:jobtype`.

  ```
  defmodule MyJob do
    use Faktory.Job, jobtype: "FooBar"
    def perform(n), do: nil
  end
  ```

  Now `{"jobtype": "FooBar", "args": [1]}` will be processed with
  `MyJob.perform/1`.

  ## Configuration

  You can globally configure all workers via `Config`.

  ```
  config :faktory_worker_ex, Faktory.Worker,
    queues: "default other-queue",
    concurrency: 5
  ```

  These options will be merged with `defaults/0` and can be seen with
  `config/0`, which in turn is merged with the argument given to `start_link/1`.

  ## Using as a module

  You can `use Faktory.Worker` which automatically does name registration and
  might make configuration a little easier.

  ```
  defmodule MyWorker do
    use Faktory.Worker, concurrency: 5, queues: "some-queue"
  end

  MyWorker.start_link()
  MyWorker.stop()
  ```

  The keyword argument to `use` will be passed to `start_link/1`.

  ## Graceful shutdown

  The `:shutdown` option specifies how long to wait for any currently running
  jobs to finish after receiving instruction to shutdown. For example from
  receiving a SIGTERM, or from the Faktory server issuing a `terminate` command
  (clicking the stop button in the web UI).

  If any jobs are still running at the end of the grace period, they will be
  `FAIL`ed on the Faktory server and brutally killed by the worker.

  ## Starting

  By default (`:start` option is `nil`), workers look at
  `Application.get_env(:faktory_worker_ex, :start_via_mix, false)` to determine if
  they should start up or not, which is set to true by `mix faktory`.

  That means all you have to do is put your worker in your supervision tree,
  then run `mix faktory` to start it up.

  You can override this by setting `:start` to either `true` or `false` for your
  worker. This gives you fine grain control over which workers to start (for
  example in an umbrella app).
  """

  @defaults [
    middleware: [],
    concurrency: 20,
    queues: ["default"],
    shutdown: 25_000,
    start: nil,
    jobtype_map: %{},
  ]

  @doc """
  Default configuration.

  ```
  #{inspect @defaults, pretty: true, width: 0}
  ```
  """
  @spec defaults() :: Keyword.t
  def defaults, do: @defaults

  @doc """
  Configuration from `Config`.

  The configuration from `Config` will be merged over `defaults/0`.

  ```
  config :faktory_worker_ex, Faktory.Worker, concurrency: 5

  iex(1)> Faktory.Worker.defaults()
  #{inspect @defaults, pretty: true, width: 0}

  iex(2)> Faktory.Worker.config()
  #{inspect Keyword.merge(@defaults, concurrency: 5), pretty: true, width: 0}
  ```
  """
  @spec config() :: Keyword.t
  def config do
    config = Application.get_application(__MODULE__)
    |> Application.get_env(__MODULE__, [])

    {:ok, modules} = Application.get_application(__MODULE__)
    |> :application.get_key(:modules)

    inferred_jobtype_map = Enum.reduce(modules, %{}, fn module, acc ->
      {:module, ^module} = Code.ensure_loaded(module)
      behaviours = module.module_info(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

      if Faktory.Job in behaviours do
        Map.put(acc, module.config[:jobtype], module)
      else
        acc
      end
    end)

    explicit_jobtype_map = Keyword.get(config, :jobtype_map, [])
    |> Map.new()

    jobtype_map = Map.merge(inferred_jobtype_map, explicit_jobtype_map)

    Keyword.merge(@defaults, config)
    |> Keyword.put(:jobtype_map, jobtype_map)
  end

  @doc """
  Start up a Faktory worker.

  The `config` argument will be merged over `config/0`.

  ## Options

  * `:concurrency` (integer) Maximum number of jobs that can be processed
    simultanteously.
  * `:queues` (binary | [binary]) Which queues to fetch jobs from.
  * `:middleware` (`Faktory.Middleware.t` | [`Faktory.Middleware.t`]) Run
    fetched jobs through middleware before processing.
  * `:shutdown` (integer) Shutdown grace period in milliseconds. The worker will
    wait this long for any currently running jobs to finish before shutting
    down.
  * `:start` (boolean | nil) If `true`, start the worker. If `false` don't
    start. If `nil` defer to `mix faktory`.
  * `:name` (`t:GenServer.name/0`) Name registration

  Connection options will be passed through to any underlying
  `Faktory.Connection` processes. If you globally configured
  `Faktory.Connection`, you may not need to set these.

  * `:host` (binary) Hostname or ip address.
  * `:port` (integer) Port.
  * `:password` (binary) If the server requires a password.
  * `:tls` (boolean) If the server uses TLS.

  """
  def start_link(config \\ []) do
    # Pop this so it doesn't overwrite jobtype_map, we want to merge instead.
    {jobtype_map, config} = Keyword.pop(config, :jobtype_map, [])

    # Merge argument with config.
    config = Keyword.merge(config(), config)

    # Merge jobtype_map.
    config = Keyword.put(config, :jobtype_map,
      Map.merge(config[:jobtype_map], Map.new(jobtype_map))
    )

    # The fetcher connection needs a wid. We can also use the wid to name our
    # stages so they can talk to each other.
    config = Keyword.put(config, :wid, Faktory.Utils.new_wid())

    # :name is a valid option, but we don't show it in config/0 or defaults/0.
    config = Keyword.put_new(config, :name, name(config))

    # Same with :module, it's like a hidden config.
    config = Keyword.put_new(config, :module, nil)

    # Normalize the queues.
    config = Keyword.update!(config, :queues, fn
      queues when is_list(queues) -> queues
      queues when is_binary(queues) -> String.split(queues, " ")
    end)

    if config[:shutdown] < 1_000 do
      raise ArgumentError, ":shutdown cannot be less than 1000 ms"
    end

    start = case config[:start] do
      nil -> Application.get_env(:faktory_worker_ex, :start_via_mix, false)
      start -> start
    end

    children = if start do
      [
        {Faktory.Stage.Fetcher, config},
        {Faktory.Stage.Worker, config},
      ]
    else
      []
    end

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: config[:name]
    )
  end

  def stop(worker) do
    Supervisor.stop(worker)
  end

  @doc false
  def name(config) do
    config[:name] || {:global, {__MODULE__, Keyword.fetch!(config, :wid)}}
  end

  @doc false
  def human_name(config) do
    case Access.fetch!(config, :name) do
      name when is_atom(name) -> inspect(name)
      name when is_tuple(name) -> Access.fetch!(config, :wid)
    end
  end

  defmacro __using__(options) do
    quote do

      @otp_app unquote(options[:otp_app])
      def otp_app, do: @otp_app

      def init(config), do: config
      defoverridable [init: 1]

      def type, do: :worker
      def client?, do: false
      def worker?, do: true

      def config, do: Faktory.Worker.config(__MODULE__)
      def child_spec(options \\ []), do: Faktory.Worker.child_spec(__MODULE__, options)

    end
  end

  @doc """
  Callback for doing runtime configuration.

  ```
  defmodule MyFaktoryWorker do
    use Faktory.Worker, otp_app: :my_app

    def init(config) do
      config
      |> Keyword.put(:host, "foo.bar")
      |> Keyword.merge(queues: ["default", "other_queue"], concurrency: 10)
    end
  end
  ```
  """
  @callback init(config :: Keyword.t) :: Keyword.t

  @doc """
  Returns a worker's config after all runtime modifications have occurred.

  ```elixir
  iex(1)> MyFaktoryWorker.config
  [
    wid: "a2ba187ec640215f",
    host: "localhost",
    port: 7419,
    middleware: [],
    concurrency: 20,
    queues: ["default"],
    password: nil,
    use_tls: false,
    reporter_count: 1,
    shutdown_grace_period: 25_000,
  ]
  ```

  Don't mess with the `wid`. 🤨
  """
  @callback config :: Keyword.t

  @doc false
  def config(module) do
    Faktory.Configuration.call(module, @defaults)
  end

  def child_spec(module, _options) do
    %{
      id: module,
      start: {Faktory.Supervisor, :start_link, [module]},
      type: :supervisor
    }
  end
end
