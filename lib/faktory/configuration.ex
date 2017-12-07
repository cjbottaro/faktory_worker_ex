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
  * `config_fn` - Callback function for runtime config. Default `nil`

  ### Client Options

    * `pool` - Client connection pool size. Default `10`
    * `middleware` - Client middleware chain. Default `[]`

  ### Worker Options

    * `pool` - Worker connection pool size. Default `${concurrency}`
    * `middleware` - Worker middleware chain. Default `[]`
    * `concurrency` - How many worker processes to start. Default `20`
    * `queues` - List of queues to fetch from. Default `["default"]`

  ### Environment variables

  It is possible to use environment variables for the configuration with the
  following format:

  ```elixir
  use Mix.Config

  config :faktory_worker_ex,
    host: {:system, "FAKTORY_HOST", "localhost"},
    port: {:system, "FAKTORY_PORT", 7419},
    client: [
      pool: 10,
    ],
    worker: [
      concurrency: 20,
      queues: ["default"],
    ]
  ```

  The format is {:system, ENV_VAR, DEFAULT}. The default can be skipped:
  {:system, ENV_VAR}

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

  alias Faktory.Utils
  alias Faktory.Configuration.{Client, Worker}

  @doc false
  def init do
    :ets.new(__MODULE__, [:set, :public, :named_table])
    init(:clients)
    init(:workers)
  end

  @doc false
  def init(:clients) do
    if get_env(:client) && get_env(:clients) do
      raise "configuration cannot have both :client and :clients"
    end

    raw_configs_for(:client)
      |> Enum.each(fn {name, config} ->
        config = resolve_config(Client, name, config)
        :ets.insert(__MODULE__, {config.name, config})
      end)
  end

  @doc false
  def init(:workers) do
    if get_env(:worker) && get_env(:workers) do
      raise "configuration cannot have both :worker and :workers"
    end

    raw_configs_for(:worker)
      |> Enum.each(fn {name, config} ->
        config = resolve_config(Worker, name, config)
        :ets.insert(__MODULE__, {config.name, config})
      end)
  end

  @doc false
  def resolve_config(type, name, config) do

    # Pull over top level options.
    config = config
      |> put_from_env(:host, :host)
      |> put_from_env(:port, :port)
      |> put_from_env(:fn, :config_fn)
      |> Keyword.put(:name, name)

    # Convert to struct.
    config = struct!(type, config)

    # Runtime configuration callback.
    config = case config.fn do
      nil -> config
      f -> f.(config)
    end

    # Add proper name and wid.
    config = %{config | name: name(type, name), wid: Utils.new_wid()}

    # Maybe default :pool to :concurrency.
    if type == Worker do
      Utils.default_from_key(config, :pool, :concurrency)
    else
      config
    end

  end

  defp name(type, name) do
    case type do
      Client -> "client/#{name}"
      Worker -> "worker/#{name}"
      _ -> "#{type}/#{name}"
    end |> String.to_atom
  end

  @doc """
  Get client or worker config.

  Resolves all the values from Mix Config, runs any runtime config callbacks,
  and returns a struct representing the config.
  """
  @spec fetch(:client | :worker, atom) :: struct
  def fetch(type, name \\ :default) do
    name = name(type, name)
    [{_name, config}] = :ets.lookup(__MODULE__, name)
    config
  end

  @doc """
  Fetch all configuration.

  Returns both client and worker configs.
  """
  @spec fetch_all :: [struct]
  def fetch_all do
    # Jeez that's some clunky syntax, Erlang.
    :ets.match(__MODULE__, {:"_", :"$1"}) |> List.flatten
  end

  @doc """
  Fetch client or worker configs.
  """
  @spec fetch_all(:client | :worker) :: [struct]
  def fetch_all(type) do
    type = case type do
      :client -> Client
      :worker -> Worker
      _ -> type
    end

    Enum.filter(fetch_all(), & &1.__struct__ == type)
  end

  defp get_env(key) do
    Application.get_env(:faktory_worker_ex, key)
    |> Utils.parse_config_value
  end

  defp put_from_env(enum, dst, src) do
    Utils.put_unless_nil(enum, dst, get_env(src))
  end

  defp raw_configs_for(type) do
    plural = "#{type}s" |> String.to_atom

    case get_env(type) do
      nil -> get_env(plural) || [{:default, []}]
      config -> [{:default, config}]
    end
  end
end
