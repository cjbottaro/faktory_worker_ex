defmodule Faktory.Configuration do
  @moduledoc """
  Configuration options for clients and workers.

  Client config is used for _enqueuing_ jobs.

  Worker config is used for _dequeuing and processing_ jobs.

  Your application may require one or the other... or both.

  ### Defaults

  ```elixir
  use Mix.Config

  config :faktory_worker_ex,
    host: "localhost",
    port: 7419,
    client: [
      pool: 10,
    ],
    worker: [
      concurrency: 20,
      queues: ["default"],
    ]
  ```

  Notice that client/worker specific options will inherit from top level options
  where applicable. In the above example, `client.host` will be `"localhost"`.

  ### Options

  * `host` - Faktory server host. Default `"localhost"`
  * `port` - Faktory server port. Default `7419`
  * `password` - Faktory server password. Default `nil`
  * `config_fn` - Callback function for runtime config. Default `nil`

  ### Client Options

    * `pool` - Client connection pool size. Default `10`
    * `middleware` - Client middleware chain. Default `[]`

  ### Worker Options

    * `pool` - Worker connection pool size. Default `${concurrency}`
    * `middleware` - Worker middleware chain. Default `[]`
    * `concurrency` - How many worker processes to start. Default `20`
    * `queues` - List of queues to fetch from. Default `["default"]`

  ### Runtime Configuration

  You can specify a callback to do runtime configuration. For example, to read
  host and port from environment variables.

  ```elixir
  config :faktory_worker_ex,
    config_fn: &FaktoryConfig.call/1

  defmodule FaktoryConfig do
    def call(config) do
      %{ config |
         host: System.get_env("FAKTORY_HOST"),
         port: System.get_env("FAKTORY_PORT") }
    end
  end
  ```

  The function takes a config struct and returns a config struct.

  ### Example

  ```elixir
  config :faktory_worker_ex,
    host: "faktory.company.com",
    client: [
      pool: 5,
      middleware: [Statsd]
    ],
    worker: [
      concurrency: 10,
      queues: ["priority01", "priority02", "priority03"]
    ]
  ```
  """

  def all do
    Enum.map(modules(), fn module ->
      {module, Map.delete(module.config, :module)}
    end)
  end

  # We allow for runtime configuration via environment variables and the init/1
  # callback. Also, wid needs to be determined at runtime. Once that's all
  # done, we memoize the config so the wid doesn't change and we don't waste
  # cpu cycles recalculating the dynamic config.
  @doc false
  def config(module, defaults) do
    import Application, only: [get_env: 2, put_env: 3]
    import Faktory.Utils, only: [new_wid: 0]

    memoized_key = {module, :memoized}

    if get_env(:faktory_worker_ex, memoized_key) do
      get_env(:faktory_worker_ex, module)
    else
      put_env(:faktory_worker_ex, memoized_key, true)
      config = get_env(:faktory_worker_ex, module)
      config = Keyword.merge(defaults, config)
        |> Keyword.put(:wid, new_wid())
        |> module.init
        |> resolve_all_env_vars
        |> Keyword.put(:module, module)
        |> Keyword.put(:type, module.type)
        |> Map.new
      put_env(:faktory_worker_ex, module, config)
      config
    end
  end

  # Get all configuration modules. Gets both clients and workers.
  @doc false
  def modules do
    Application.get_all_env(:faktory_worker_ex)
      |> Enum.reduce([], fn {module, _}, acc ->
        try do
          module.config
          module.client?
          module.worker?
          [module | acc]
        rescue
          UndefinedFunctionError -> acc
        end
      end)
      |> Enum.reverse
  end

  @doc false
  def modules(type) do
    Enum.filter(modules, & &1.type == type)
  end

  # Return the default (first defined) client module.
  @doc false
  def default_client do
    Enum.find(modules(), & &1.client?) || raise Faktory.Error.NoClientsConfigured
  end

  # Return true if the given module is a configuration module.
  @doc false
  def exists?(module), do: !!Enum.find(modules(), & &1 == module)

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
    name = to_string(name) |> String.upcase
    System.get_env(name) || default
  end

end
