defmodule Faktory.Configuration do
  @moduledoc """
  Configuration options for clients and workers.

  Client config is used for _enqueuing_ jobs.

  Worker config is used for _dequeuing and processing_ jobs.

  Your application may require one or the other... or both.

  ### Defaults

  If you don't configure `faktory_worker_ex` at all, it will autoconfigure
  itself to connect to a Faktory server on `localhost` both client side and
  worker side with sane defaults. You can call `Faktory.Configuration.all/0`
  to see these defaults.

  ### Client Configuration

    Settings used for _enqueuing_ jobs.

    ```elixir
    config :faktory_worker_ex, FooConfig,
      adapter: Faktory.Configuration.Client
      host: "foo_faktory.mycompany.com",

    config :faktory_worker_ex, BarConfig
      adapter: Faktory.Configuration.Client
      host: "bar_faktory.mycompany.com"
    ```

    Valid options:

    * `host` - Host of Faktory server. Default `"localhost"`
    * `port` - Port of Faktory server. Default `7419`
    * `pool` - Connection pool size. Default `10`
    * `middleware` - Middleware chain. Default `[]`
    * `password` - For Faktory server authentication. Default `nil`
    * `use_tls` - Connect to Faktory server using TLS. Default `false`

  ### Default Client

  The first configured client is the "default client" and is used by
  `Faktory.Job.perform_async/2` when no client is specified.

  ```elixir
  # No client is specified, default client is used.
  MySuperJob.perform_async([1, 2, 3])

  # Explicitly specify a client.
  MyUltraJob.perform_async([1, 2, 3], client: BarConfig)
  ```

  ### Worker Options

    ```elixir
    config :faktory_worker_ex, FooWorker,
      adapter: Faktory.Configuration.Worker,
      host: "foo_faktory.mycompany.com"

    config :faktory_worker_ex, BarWorker,
      adapter: Faktory.Configuration.Worker,
      host: "bar_faktory.mycompany.com"
    ```

    Valid options:

    * `host` - Host of Faktory server. Default `"localhost"`
    * `port` - Port of Faktory server. Default `7419`
    * `concurrency` - How many concurrent jobs to process. Default `20`
    * `pool` - Connection pool size. Default `${concurrency}`
    * `middleware` - Middleware chain. Default `[]`
    * `queues` - List of queues to fetch from. Default `["default"]`

  ### Runtime Configuration

  There are two ways to do runtime configuration:
  1. The conventional tuple syntax to read environment vars
  1. Using a callback function

  Environment var without default value:
  ```elixir
  config :faktory_worker_ex, MyClient,
    adapter: Faktory.Configuration.Client,
    host: {:system, "FAKTORY_HOST"}
  ```

  Environment var with default value:
  ```elixir
  config :faktory_worker_ex, MyClient,
    adapter: Faktory.Configuration.Client,
    host: {:system, "FAKTORY_HOST", "localhost"}
  ```

  Using a callback:
  ```elixir
  config :faktory_worker_ex, MyClient,
    adapter: Faktory.Configuration.Client,

  defmodule MyClient do
    use Faktory.Configuration.Client

    def init(config) do
      Keyword.put(config, :host, "faktory.company.com")
    end
  end
  ```
  """

  alias Faktory.{Configuration, Logger}
  import Faktory, only: [get_env: 1, get_env: 2, put_env: 2, get_all_env: 0]

  @doc false
  def init do
    put_env(:config_modules, [])

    get_all_env()
      |> Enum.each(fn {module, options} ->
        case get_adapter(options) do
          nil -> nil
          adapter -> configure(module, adapter, options)
        end
      end)

    if Enum.empty?(modules(:client)) do
      Logger.info("No clients configured, autoconfiguring for localhost")
      module = FaktoryDefaultClient
      adapter = Configuration.Client
      get_or_create_config_module(module, adapter)
      configure(module, adapter, [adapter: adapter])
    end

    if Enum.empty?(modules(:worker)) && Faktory.start_workers? do
      Logger.info("No workers configured, autoconfiguring for localhost")
      module = FaktoryDefaultWorker
      adapter = Configuration.Worker
      get_or_create_config_module(module, adapter)
      configure(module, adapter, [adapter: adapter])
    end

    # So that things like default_client/0 work properly.
    modules = get_env(:config_modules) |> Enum.reverse
    put_env(:config_modules, modules)
  end

  @doc """
  Return all configuration modules and their options.

  This is more or less a debugging function.
  """
  @spec all() :: [{module, map}]
  def all do
    Enum.map(modules(), & {&1, &1.config})
  end

  # Get all configuration modules. Gets both clients and workers.
  @doc false
  def modules do
    get_env(:config_modules, [])
  end

  @doc false
  def modules(type) do
    Enum.filter(modules(), & &1.type == type)
  end

  # Return the default (first defined) client module.
  @doc false
  def default_client do
    Enum.find(modules(), & &1.client?) || raise Faktory.Error.NoClientsConfigured
  end

  @doc false
  def exists?(module) do
    Enum.any?(modules(), & &1 == module)
  end

  defp configure(module, adapter, options) do
    get_or_create_config_module(module, adapter)

    config = adapter.defaults
      |> Keyword.merge(options)
      |> module.init
      |> handle_cli_options(module)
      |> adapter.reconfig
      |> resolve_all_env_vars
      |> typecast
      |> Keyword.put(:wid, Faktory.Utils.new_wid)
      |> Keyword.put(:module, module)
      |> Map.new

    put_env(module, config)

    modules = get_env(:config_modules)
    put_env(:config_modules, [module | modules])
  end

  defp resolve_all_env_vars(config) do
    Enum.map(config, fn {k, v} ->
      v = case v do
        {:system, name, default} -> resolve_env_var(name, default)
        {:system, name} -> resolve_env_var(name)
        v -> v
      end
      {k, v}
    end)
  end

  defp resolve_env_var(name, default \\ nil) do
    (name |> to_string |> System.get_env) || default
  end

  defp get_or_create_config_module(module, adapter) do
    if !Code.ensure_loaded?(module) do
      definition = quote do: use unquote(adapter)
      defmodule module, do: Module.eval_quoted(__MODULE__, definition)
    end
    module
  end

  defp get_adapter(options) do
    if Keyword.keyword?(options) do
      options[:adapter]
    else
      nil
    end
  end

  defp handle_cli_options(options, module) do
    if module.worker? do # CLI options only applicable to workers?
      cli_options = get_env(:cli_options, [])
      cli_options = cli_options
        |> Faktory.Utils.put_unless_nil(:use_tls, cli_options[:tls])
        |> Keyword.delete(:tls)
      Keyword.merge(options, cli_options)
    else
      options
    end
  end

  defp typecast(options) do
    Enum.map options, fn {k, v} ->
      v = case k do
        :port -> to_integer(v)
        :pool -> to_integer(v)
        :concurrency -> to_integer(v)
        _ -> v
      end
      {k, v}
    end
  end

  defp to_integer(v), do: to_string(v) |> String.to_integer

end
