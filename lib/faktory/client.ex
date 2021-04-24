defmodule Faktory.Client do
  @moduledoc ~S"""
  Pooled connections to a Faktory server.

  This is what you want to use to enqueue jobs to the Faktory server, using
  either `push/3` directly or `c:Faktory.Job.perform_async/2`.

  ```
  defmodule MyJob do
    use Faktory.Job, client: MyClient

    def perform(n1, n2) do
      IO.puts("#{n1} plus #{n2} equals #{n1+n2}")
    end
  end

  {:ok, client} = Faktory.Client.start_link(name: MyClient)
  {:ok, job} = Faktory.Client.push(client, jobtype: "MyJob", args: [1, 2])
  {:ok, job} = MyJob.perform_async([1, 2])
  ```

  ## Using as a module

  This is nice so you don't have to constantly pass around a pid or name.

  ```
  defmodule MyClient do
    use Faktory.Client, host: "faktory.myapp.com", pool_size: 10
  end

  MyClient.start_link()
  {:ok, info} = MyClient.info()
  {:ok, job} = MyClient.push(jobtype: "MyJob", args: [1, 2])
  ```

  The keyword list argument to `use` will be passed to `start_link/1`.

  ## Default configuration

  You can override the default options that are sent to `start_link/1` using `Config`.

  ```
  config :faktory_worker_ex, Faktory.Client,
    host: "faktory.myapp.com",
    pool_size: 2,
    lazy: false
  ```

  These will be merged with `defaults/0` and can be seen with `config/0`.

  """
  @behaviour NimblePool

  @impl NimblePool
  def init_worker(config) do
    {:ok, conn} = Faktory.Connection.start_link(config)
    {:ok, conn, config}
  end

  @impl NimblePool
  def handle_checkout(:checkout, _from, conn, config) do
    {:ok, conn, conn, config}
  end

  @type t :: GenServer.server()

  @defaults [
    pool_size: 5,
    lazy: true,
  ]
  @doc """
  Default configuration.

  ```
  #{inspect @defaults, pretty: true, width: 0}
  ```
  """
  @spec defaults() :: Keyword.t
  def defaults do
    @defaults
  end

  @doc """
  Configuration from `Config`.

  The options specified with `Config` will be merged with `defaults/0`.

  ```
  config :faktory_worker_ex, #{inspect __MODULE__}, pool_size: 2

  iex(1)> #{inspect __MODULE__}.config()
  #{inspect Keyword.merge(@defaults, pool_size: 2), pretty: true, width: 0}
  ```
  """
  @spec config() :: Keyword.t
  def config do
    config = Application.get_application(__MODULE__)
    |> Application.get_env(__MODULE__, [])

    Keyword.merge(@defaults, config)
  end

  @doc """
  Start up a client.

  `opts` is merged over `config/0`. All options are optional.

  ## Options

  * `:pool_size` (integer) how many connections are in the pool.
  * `:lazy` (boolean) true if the connections are to started lazily.
  * `:name` (`t:GenServer.name/0`) for GenServer name registration.

  All remaining options are passed to `Faktory.Connection.start_link/1`.

  ## Examples

  ```
  {:ok, client} = #{inspect __MODULE__}.start_link(host: "foo.bar.com", name: MyClient)

  {:ok, client} = #{inspect __MODULE__}.start_link(pool_size: 2, lazy: false)
  ```
  """
  def start_link(opts \\ []) do
    {pool_opts, config} = Keyword.split(opts, [:pool_size, :lazy, :name])

    @defaults
    |> Keyword.merge(pool_opts)
    |> Keyword.put(:worker, {__MODULE__, config})
    |> NimblePool.start_link()
  end

  @doc """
  Get a connection from the pool.

  The connection is returned to the pool automatically after the function is run.

  You shouldn't really need to use this function.
  ```
  {:ok, info} = #{inspect __MODULE__}.with_conn(client, fn conn ->
    Faktory.Connection.info(conn)
  end)
  ```
  """
  @spec with_conn(t, (Faktory.Connection.t -> any)) :: any
  def with_conn(client, f) do
    NimblePool.checkout!(client, :checkout, fn _, conn ->
      {f.(conn), conn}
    end)
  end

  @doc """
  Get Faktory server info.

  See `Faktory.Connection.info/1`.
  """
  @spec info(t) :: {:ok, map} | {:error, term}
  def info(client) do
    with_conn(client, fn conn -> Faktory.Connection.info(conn) end)
  end

  @doc """
  Enqueue a job.

  See `Faktory.Connection.push/3`.
  """
  @spec push(t, Faktory.push_job, Keyword.t) :: {:ok, Faktory.push_job} | {:error, term}
  def push(client, job, opts \\ []) do
    with_conn(client, fn conn -> Faktory.Connection.push(conn, job, opts) end)
  end

  @doc """
  Reset Faktory server.

  See `Faktory.Connection.flush/1`.
  """
  @spec flush(t) :: :ok | {:error, term}
  def flush(client) do
    with_conn(client, fn conn -> Faktory.Connection.flush(conn) end)
  end

  @doc """
  Mutate API

  See `Faktory.Connection.mutate/2`.
  """
  @spec mutate(t, Keyword.t | map) :: :ok | {:error, term}
  def mutate(client, mutation) do
    with_conn(client, fn conn -> Faktory.Connection.mutate(conn, mutation) end)
  end

  # def fetch(client, queues, opts \\ []) do
  #   with_conn(client, fn conn -> Faktory.Connection.fetch(conn, queues, opts) end)
  # end

  # def ack(client, jid) do
  #   with_conn(client, fn conn -> Faktory.Connection.ack(conn, jid) end)
  # end

  # def fail(client, jid, errtype, message, backtrace \\ []) do
  #   with_conn(client, fn conn -> Faktory.Connection.fail(conn, jid, errtype, message, backtrace) end)
  # end

end
