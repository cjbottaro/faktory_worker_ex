defmodule Faktory.Configuration do
  @moduledoc """
  Configure clients (enqueuing) and workers (dequeing/processing).

  Client configuration is for enqueuing jobs. Worker configuration is for
  dequeing and processing jobs. You may have an app that only needs one or the
  other... or both!

  Configuration is done by defining modules then telling `faktory_worker_ex` about them.

  ### Compile time configuration

  ```elixir
    defmodule ClientConfig do
      use Faktory.Configuration, :client

      host "localhost"
      port 7419
      pool 10
    end

    defmodule WorkerConfig do
      use Faktory.Configuration, :worker

      host "localhost"
      port 7419
      concurrency 20
      pool 10
      queues ["default"]
    end
  ```

  All the configuration options have sane defaults (pretty much exactly what
  the example above shows).

  ### Runtime configuration

  You can set/update any configuration at runtime by defining a function.

  ```elixir
  defmodule ClientConfig do
    use Faktory.Configuration, :client

    def update(old_config) do
      new_config = Keyword.put(old_config, :pool, old_config[:pool] + 1)
      new_config
    end
  end
  ```

  ### Activating the configuration.

  In your Mix Config files (`config/config.exs`)...

  ```elixir
  use Mix.Config

  config :faktory_worker_ex,
    client_config: ClientConfig,
    worker_config: WorkerConfig
  ```

  Note that workers will only run via the mix task (`mix faktory`), despite
  having an active worker configuration!
  """

  @doc ~S"""
  Runtime configuration.

  Define this callback to set configuration at runtime.

  `config` is the existing config.

  Return value is the updated config.

  ## Example

  Set host and port from environment vars.

  ```elixir
    def update(config) do
      Keyword.merge(config,
        host: System.get_env("FAKTORY_HOST"),
        port: System.get_env("FAKTORY_PORT")
      )
    end
  ```
  """
  @callback update(config :: Keyword.t) :: Keyword.t

  defmacro __using__(type) do
    quote do

      @behaviour Faktory.Configuration

      import Faktory.Configuration, only: [
        host: 1, port: 1, pool: 1, concurrency: 1, queues: 1, middleware: 1
      ]
      import Keyword, only: [merge: 2]

      # Common defaults
      @config [host: "localhost", port: 7419, middleware: []]
      @config_type unquote(type) # @type is special, can't use it.

      case unquote(type) do
        :client ->
          @config merge(@config, pool: 10)
        :worker ->
          @config merge(@config, pool: nil, concurrency: 20, queues: ["default"])
      end

      def config_type, do: @config_type
      def update(config), do: config

      defoverridable [update: 1]

      @before_compile Faktory.Configuration
    end
  end

  defmacro __before_compile__(_env) do
    quote do

      def all do
        alias Faktory.{Configuration, Utils}
        import Configuration, only: [worker_special: 2]

        case :ets.lookup(Configuration, __MODULE__) do
          [{__MODULE__, config} | []] -> config
          _ ->
            config = @config
              # Let user do runtime config.
              |> update
              # Always put these in.
              |> Keyword.put(:wid, Utils.new_wid)
              |> Keyword.put(:config_module, __MODULE__)
              # If we're a worker config, do special stuff
              |> worker_special(config_type())
              # Turn it into a map with atom keys.
              |> Utils.atomify_keys
              |> IO.inspect

            # Cache and return it.
            :ets.insert(Configuration, {__MODULE__, config})
            config
        end
      end

    end
  end

  @doc """
  Set the host to connect to.

  Valid for both client and worker configuration. Default `"localhost"`
  """
  @spec host(String.t) :: Keyword.t
  defmacro host(host) do
    quote do
      @config Keyword.merge(@config, host: unquote(host))
    end
  end

  @doc """
  Set the port to connect to.

  Valid for both client and worker configuration. Default `7419`
  """
  @spec port(integer) :: Keyword.t
  defmacro port(port) do
    quote do
      @config Keyword.merge(@config, port: unquote(port))
    end
  end

  @doc """
  Set the connection pool size.

  Valid for both client and worker configuration. Default `10`
  """
  @spec pool(integer) :: Keyword.t
  defmacro pool(pool) do
    quote do
      @config Keyword.merge(@config, pool: unquote(pool))
    end
  end

  @doc """
  Set the max number of concurrent jobs that can be processed at a time.

  Valid only for worker configuration. Default `20`
  """
  @spec concurrency(integer) :: Keyword.t
  defmacro concurrency(concurrency) do
    quote do
      @config Keyword.merge(@config, concurrency: unquote(concurrency))
    end
  end

  @doc """
  Set the queues to fetch jobs from.

  Valid only for worker configuration. Default `["default"]`
  """
  @spec queues([String.t]) :: Keyword.t
  defmacro queues(queues) do
    quote do
      @config Keyword.merge(@config, queues: unquote(queues))
    end
  end

  @doc """
  Set the middleware chain to use.

  Valid for both client and worker configurations. Default `[]`
  """
  @spec middleware([module]) :: Keyword.t
  defmacro middleware(chain) do
    quote do
      @config Keyword.merge(@config, middleware: unquote(chain))
    end
  end

  @doc false
  # Helper function to add CLI options to config if is worker config.
  def worker_special(config, :client), do: config
  def worker_special(config, :worker) do
    alias Faktory.Utils
    cli_options = Faktory.get_env(:cli_options)
    queues = cli_options[:queues] && (
      cli_options[:queues] |> String.split(",")
    )
    config
      # CLI overrides
      |> Utils.put_unless_nil(:concurrency, cli_options[:concurrency])
      |> Utils.put_unless_nil(:queues, queues)
      |> Utils.put_unless_nil(:pool, cli_options[:pool])
      # Default pool to concurrency
      |> Utils.default_from_key(:pool, :concurrency)
  end


end
