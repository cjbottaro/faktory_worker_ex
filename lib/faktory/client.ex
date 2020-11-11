defmodule Faktory.Client do
  alias Faktory.Protocol

  @moduledoc """
  Create and configure a client for _enqueing_ jobs.

  It works similarly to configuring an Ecto Repo.

  ```elixir
  defmodule MyFaktoryClient do
    use Faktory.Client, otp_app: :my_app
  end

  # It must be added to your app's supervision tree
  defmodule MyApp.Application do
    use Application

    def start(_type, _args) do
      children = [MyFaktoryClient]
      Supervisor.start_link(children, strategy: :one_for_one)
    end
  end
  ```

  ## Defaults

  See `defaults/0` for default client configuration.

  ## Compile time config

  Done with `Config`.

  ```elixir
  import Config

  config :my_app, MyFaktoryClient,
    host: "foo.bar",
    port: 1000
    pool: 10
  ```

  ## Runtime config

  Can be done with the `c:init/1` callback.

  Can be done with environment variable tuples:
  ```elixir
  import Config

  config :my_app, MyFaktoryClient,
    host: {:system, "FAKTORY_HOST"} # No default, errors if FAKTORY_HOST doesn't exist
    port: {:system, "FAKTORY_PORT", 1001} # Use 1001 if FAKTORY_PORT doesn't exist
  ```
  """

  @defaults [
    host: "localhost",
    port: 7419,
    pool: 5,
    middleware: [],
    password: nil,
    use_tls: false
  ]

  @doc """
  Return the default client configuration.

  ```elixir
  iex(3)> Faktory.Client.defaults
  [
    host: "localhost",
    port: 7419,
    pool: 5,
    middleware: [],
    password: nil,
    use_tls: false,
    default: false
  ]
  ```
  """
  @spec defaults :: Keyword.t
  def defaults, do: @defaults

  defmacro __using__(options) do
    quote do

      @otp_app unquote(options[:otp_app])
      def otp_app, do: @otp_app

      def init(config), do: config
      defoverridable [init: 1]

      def type, do: :client
      def client?, do: true
      def worker?, do: false

      def config, do: Faktory.Client.config(__MODULE__)
      def child_spec(_opt \\ []), do: Faktory.Client.child_spec(__MODULE__)
      def push(job, options \\ []), do: Faktory.Client.push(__MODULE__, job, options)
      def info(), do: Faktory.Client.info(__MODULE__)
      def flush(), do: Faktory.Client.flush(__MODULE__)

    end
  end

  @doc """
  Callback for doing runtime configuration.

  ```
  defmodule MyFaktoryClient do
    use Faktory.Client, otp_app: :my_app

    def init(config) do
      config
      |> Keyword.put(:host, "foo.bar")
      |> Keyword.merge(port: 1001, pool: 10)
    end
  end
  ```
  """
  @callback init(config :: Keyword.t) :: Keyword.t

  @doc """
  Returns a client's final config including all compile time and runtime configurations.

  ```elixir
  iex(5)> MyFaktoryClient.config
  [
    port: 1001,
    host: "foo.bar",
    pool: 10,
    middleware: [],
    password: nil,
    use_tls: false,
    default: true
  ]
  ```
  """
  @callback config :: Keyword.t

  @doc """
  Lower level enqueing function.

  Manually enqueue a Faktory job. A job is defined here:
  https://github.com/contribsys/faktory/wiki/The-Job-Payload

  This function will set the JID for you, you do not have to set it yourself.

  `options` is a keyword list specifying...

  `:middleware` Send the job through this middleware.

  Ex:
  ```elixir
    push(%{"jobtype" => "MyFunWork", "args" => [1, 2, "three"], "queue" => "somewhere"})
    push(job, middleware: TheJobMangler)
  ```
  """
  @callback push(job :: map, options :: Keyword.t) :: {:ok, job :: map} | {:error, reason :: binary}


  @doc """
  Get info from the Faktory server.

  Returns the info as a map (parsed JSON).
  """
  @callback info() :: map

  @doc """
  Flush (clear) the Faktory db.

  All job info will be lost.
  """
  @callback flush :: :ok | {:error, binary}

  @doc false
  def config(module) do
    Faktory.Configuration.call(module, @defaults)
  end

  @doc false
  def child_spec(module) do
    config = module.config
    name = config[:name] || module

    pool_options = [
      name: {:local, name},
      worker_module: Faktory.Connection,
      size: config[:pool],
      max_overflow: 2
    ]

    # I can't think of a better place to put this since we're not starting
    # a GenServer that we control. Ideally this would be put in the init/1
    # callback when starting up a "Client".
    if !Faktory.get_env(:default_client) do
      Faktory.put_env(:default_client, module)
    end

    :poolboy.child_spec(module, pool_options, config)
  end

  @doc false
  def push(module, job, options) do
    import Faktory.Utils, only: [new_jid: 0, if_test: 1, blank?: 1]
    alias Faktory.Middleware

    if blank?(job["jobtype"]) do
      {:error, "missing required field jobtype"}
    else

      middleware = if Keyword.has_key?(options, :middleware) do
        options[:middleware] || []
      else
        module.config[:middleware]
      end

      job = if blank?(job["jid"]) do
        Map.put(job, "jid", new_jid())
      else
        job
      end

      # To facilitate testing, we keep a map of jid -> pid and send messages to
      # the pid at various points in the job's lifecycle.
      if_test do: TestJidPidMap.register(job["jid"])

      result = Middleware.traverse(job, middleware, fn job ->
        :poolboy.transaction(module, &Protocol.push(&1, job))
      end)

      case result do
        {:ok, _} ->
          %{ "jid" => jid, "args" => args, "jobtype" => jobtype} = job
          args = Faktory.Utils.args_to_string(args)
          Faktory.Logger.info "Q 📥 #{inspect self()} jid-#{jid} (#{jobtype}) #{args}"
          {:ok, job}

        error -> error
      end
    end
  end

  def info(module) do
    :poolboy.transaction(module, &Protocol.info(&1))
  end

  def flush(module) do
    :poolboy.transaction(module, &Protocol.flush(&1))
  end

end
