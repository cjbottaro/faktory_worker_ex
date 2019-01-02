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

  def call(module, defaults) do
    config = Application.get_env(module.otp_app, module, [])
    if config[:configured] do
      Keyword.delete(config, :configured)
    else
      config = defaults
      |> Keyword.merge(config)
      |> module.init
      |> put_wid(module.type) # Client connection don't have wid.
      |> resolve_all_env_vars
      |> normalize
      |> Keyword.put(:configured, true)
      Application.put_env(module.otp_app, module, config)
      call(module, defaults)
    end
  end

  defp put_wid(config, :worker), do: Keyword.put(config, :wid, Faktory.Utils.new_wid)
  defp put_wid(config, :client), do: config

  def resolve_all_env_vars(config) do
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

  def normalize(config) do
    case config[:port] do
      port when is_binary(port) ->
        port = String.to_integer(port)
        Keyword.put(config, :port, port)
      port when is_integer(port) ->
        config
    end
  end

end
