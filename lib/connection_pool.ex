defmodule ConnectionPool do
  @moduledoc """
  Pooling for GenServers.

  Notable features
  * Connections are dynamically supervised named GenServers.
  * Connections are lazily started.
  * Connections are automatically checked in if the owner process dies.
  * Telemetry events.

  ## Named GenServers

  Each connection is a named GenServer that is dynamically supervised. This
  allows the connection to be restarted and continue to be used without having
  to get a new pid.

  ```
  {:ok, pool} = ConnectionPool.start_link(...)
  {:ok, conn} = ConnectionPool.checkout(pool)
  {:ok, result} = SomeConnection.do_something(conn)

  GenServer.whereis(conn) |> Process.exit(:kill)

  # Still works because dynamic supervisor restarted connection.
  {:ok, result} = SomeConnection.do_something(conn)

  :ok = ConnectionPool.checkout(pool, conn)
  ```

  ## Start Spec

  You must provide a "start spec" that let's `ConnectionPool` know how to start
  your connections, including how to name them. It is a function that takes a
  name as an argument.

  ```
  {:ok, pool} = ConnectionPool.start_link(start: fn name ->
    {SomeConnection, :start_link, [[host, "foo.com", name: name]]}
  end)
  ```

  ## Configuration

  There is a robust (but simple) configuration system that allows for both
  compile time and run time configuration.

  See `defaults/0` and `config/0` for more info.

  ## Using as a Module

  ```
  defmodule MyPool do
    use ConnectionPool,
      start: fn -> ... end,
      size: 5,
      timeout: 2_000
  end

  MyPool.start_link()
  {:ok, conn} = MyPool.checkout()
  :ok = MyPool.checkin(conn)
  ```

  You can specify a `c:start_spec/1` callback in lieu of providing the `:start`
  option.

  You can specify configuration specific to your module. See `c:config/0` for
  more info.

  ## Telemetry Events

  You can see these events in action by calling:
  ```
  :ok = ConnectionPool.Telemetry.init_logging()
  ```

  How long `checkin/2` took:
  ```
  [
    [:connection_pool, :checkin],
    %{usec: usec},
    %{result: result}
  ]
  ```

  How long `checkout/2` took:
  ```
  [
    [:connection_pool, :checkout],
    %{usec: usec},
    %{result: result}
  ]
  ```

  How long a connection was checked out for:
  ```
  [
    [:connection_pool, :checkout, :duration],
    %{usec: usec},
    %{conn: conn}
  ]
  ```

  When a connection is automatically checked in due to a process ending. The time
  reported is how long it was checked out for:
  ```
  [
    [:connection_pool, :checkout, :reaped],
    %{usec: usec},
    %{conn: conn, reason: reason}
  ]
  ```
  """

  use GenServer

  defmacro __using__(config \\ []) do
    quote do
      @config unquote(config)

      def config do
        Keyword.merge(ConnectionPool.config(), @config)
      end

      def start_spec(name), do: "not implemented"
      defoverridable(start_spec: 1)

      def child_spec(config) do
        %{
          id: {ConnectionPool, __MODULE__},
          start: {__MODULE__, :start_link, [config]}
        }
      end

      def start_link(config \\ []) do
        Keyword.merge(config(), config)
        |> Keyword.put_new(:start, &start_spec/1)
        |> ConnectionPool.start_link(name: __MODULE__)
      end

      def debug do
        ConnectionPool.debug(__MODULE__)
      end

      def checkout(opts \\ [], f \\ nil) do
        ConnectionPool.checkout(__MODULE__, opts, f)
      end

      def checkin(conn) do
        ConnectionPool.checkin(__MODULE__, conn)
      end

    end
  end

  @type pool :: GenServer.server()
  @type conn :: GenServer.server()

  @defaults [
    start: nil,
    size: 10,
    timeout: 5_000,
  ]

  @doc """
  Specific connection pool configuation.

  The module's specific configuration will be merged with `config/0`.

  ```
  config :connection_pool, ConnectionPool, timeout: 1_000
  config :my_app, MyPool, size: 2

  iex(1)> ConnectionPool.config()
  #{inspect Keyword.merge(@defaults, timeout: 1_000), pretty: true, width: 0}

  iex(2)> MyPool.config()
  #{inspect Keyword.merge(@defaults, timeout: 1_000, size: 2), pretty: true, width: 0}
  ```
  """
  @callback config :: Keyword.t

  @doc """
  Returns a specification to start this module under a supervisor.

  ```
  defmodule MyPool do
    use ConnectionPool
  end

  children = [MyPool]
  Supervisor.start_link(children, strategy: :one_for_one)

  children = [{MyPool, size: 5}]
  Supervisor.start_link(children, strategy: :one_for_one)
  ```
  """
  @callback child_spec(config :: Keyword.t) :: Supervisor.child_spec()

  @doc """
  See `checkout/2`.
  """
  @callback checkout(opts :: Keyword.t) :: {:ok, conn} | {:error, term}

  @doc """
  See `checkin/2`.
  """
  @callback checkin(conn) :: :ok | {:error, term}

  @doc """
  See `transaction/3`.
  """
  @callback transaction(opts :: Keyword.t, (conn -> term)) :: {:ok, term} | {:error, term}

  @doc """
  Alternative to the `:start` option.

  You can use this instead of specifying the `:start` option.
  ```
  defmodule MyPool do
    use ConnectionPool, size: 2

    def start_spec(name) do
      {SomeConnection, :start_link, [[name: name]]}
    end
  end
  ```
  """
  @callback start_spec(name :: GenServer.name()) :: {atom, atom, [term]}

  @doc """
  Start the connection pool.

  `config` is merged with `c:config/0`.

  See `start_link/2` for more details.
  """
  @callback start_link(config :: Keyword.t) :: GenServer.on_start()

  @doc """
  Default configuration for all connection pools.

  ```
  iex(1)> ConnectionPool.defaults()
  #{inspect @defaults, pretty: true, width: 0}
  ```
  """
  @spec defaults :: Keyword.t
  def defaults, do: @defaults

  @doc """
  Merged configuration.

  Takes any configuration found via `Config` and merges it with `defaults/0`.
  ```
  iex(1)> ConnectionPool.config()
  #{inspect @defaults, pretty: true, width: 0}

  config :connection_pool, ConnectionPool, size: 2

  iex(2)> ConnectionPool.config()
  #{inspect Keyword.put(@defaults, :size, 2), pretty: true, width: 0}
  ```
  """
  @spec config :: Keyword.t
  def config do
    config = Application.get_application(__MODULE__)
    |> Application.get_env(__MODULE__, [])

    Keyword.merge(@defaults, config)
  end

  @doc false
  def debug(pool) do
    GenServer.call(pool, :debug)
  end

  @doc """
  Checkout a connection from the pool.

  A `:timeout` option can be given (in milliseconds or `:infinity`) that
  specifies how long to wait if no connection is available in the pool.

  If no `:timeout` option is specified, the one from `config/0` is used.

  Processes that are waiting on connections are replied to in first come, first
  serve order.
  """
  @spec checkout(pool, Keyword.t) :: {:ok, conn} | {:error | :timeout} | {:error, term}
  def checkout(pool, opts \\ []) do
    {usec, result} = :timer.tc(fn ->
      GenServer.call(pool, {:checkout, opts}, :infinity)
    end)

    :telemetry.execute(
      [:connection_pool, :checkout],
      %{usec: usec},
      %{result: result}
    )

    result
  end

  def transaction(pool, opts \\ [], f) do
    with {:ok, conn} <- checkout(pool, opts) do
      try do
        {:ok, f.(conn)}
      after
        checkin(pool, conn)
      end
    end
  end

  def checkin(pool, conn) do
    {usec, result} = :timer.tc(fn ->
      GenServer.call(pool, {:checkin, conn})
    end)

    :telemetry.execute(
      [:connection_pool, :checkin],
      %{usec: usec},
      %{result: result}
    )

    result
  end

  @doc """
  Returns a specification to start this module under a supervisor.
  """
  @spec child_spec({config :: Keyword.t, gen_opts :: Keyword.t}) :: Supervisor.child_spec()
  def child_spec({config, gen_opts}) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [config, gen_opts]}
    }
  end

  @spec child_spec(config :: Keyword.t) :: Supervisor.child_spec()
  def child_spec(config) do
    super(config)
  end


  @doc """
  Start a connection pool.

  The given `config` is merged with `config/0`.

  `gen_opts` are passed to the underlying `GenServer.start_link/3` as the last
  argument.

  ## Options for `config`

  `:start` defines how the pool will create a connection (GenServer). It's a
  function that takes a name as an argument. The connection must be named using
  that name.
  ```
  fn name -> {SomeConnection, :start_link, [[name: name]]} end
  ```

  `:size` is an integer specifying the maximum number of connections the pool
  will have.

  `:timeout` an integer (or `:infinity`) specifying how long `checkout/2` will
  wait for an available connection.

  ## Examples
  ```
  start = fn name ->
    {Faktory.Client, :start_link, [[host: "foo.bar"], [name: name]]}
  end

  {:ok, pool} = ConnectionPool.start_link(start: start)
  {:ok, pool} = ConnectionPool.start_link(start: start, timeout: 1_000)
  {:ok, pool} = ConnectionPool.start_link(start: start, timeout: 2_000, size: 5)
  ```
  """
  @spec start_link(Keyword.t, Keyword.t) :: {:ok, pid} | {:error, term}
  def start_link(config \\ [], gen_opts \\ []) when is_list(config) and is_list(gen_opts) do
    config = Keyword.merge(config(), config)
    GenServer.start_link(__MODULE__, config, gen_opts)
  end

  @doc false
  def init(config) do
    config = Map.new(config)

    {module, _, _} = config.start.(nil)

    names = Enum.map(1..config.size, fn _ ->
      id = :crypto.strong_rand_bytes(7) |> Base.encode16(case: :lower)
      {:global, {module, id}}
    end)

    state = %{
      config: config,
      module: module,
      checked_in: names,
      checked_out: %{},
      checkout_time: %{},
      started: MapSet.new(),
      waiting: :ordsets.new(),
    }

    {:ok, state}
  end

  def handle_call(:debug, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:checkout, opts}, {pid, _ref} = from, state) do
    %{checked_in: checked_in, checked_out: checked_out} = state

    if not Map.has_key?(checked_out, pid) do
      Process.monitor(pid)
    end

    if checked_in == [] do
      {:noreply, add_waiter(from, opts, state)}
    else
      {name, state} = check_out(pid, state)
      case ensure_started(name, state) do
        {:ok, state} -> {:reply, {:ok, name}, state}
        error -> {:reply, error, check_in(name, pid, state)}
      end
    end
  end

  def handle_call({:checkin, name}, {pid, _ref}, state) do
    %{checked_out: checked_out} = state

    if name in (checked_out[pid] || []) do
      state = check_in(name, pid, state)
      {:reply, :ok, reply_to_waiter(name, state)}
    else
      {:reply, {:error, "not checked out"}, state}
    end
  end

  def handle_info({:checkout_timeout, from}, state) do
    %{waiting: waiting} = state

    # Sorry you got timed out.
    :ok = GenServer.reply(from, {:error, :timeout})

    # Proactively remove them from the waiters. Not sure how to do this the most
    # efficiently.
    waiting = Enum.reject(waiting, fn {_time, waiter, _timer} -> waiter == from end)

    {:noreply, %{state | waiting: waiting}}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    %{checked_out: checked_out, checkout_time: checkout_time} = state

    state = Enum.reduce(checked_out[pid] || [], state, fn name, state ->
      :telemetry.execute(
        [:connection_pool, :checkout, :reaped],
        %{usec: monotonic_time() - checkout_time[name]},
        %{conn: name, reason: reason}
      )

      check_in(name, pid, state)
    end)

    {:noreply, state}
  end

  # No error checking; must be done upstream.
  defp check_out(pid, state) do
    %{checked_in: checked_in, checked_out: checked_out, checkout_time: checkout_time} = state

    [name | checked_in] = checked_in
    checked_out = Map.update(checked_out, pid, MapSet.new([name]), &MapSet.put(&1, name))
    checkout_time = Map.put(checkout_time, name, monotonic_time())

    {name, %{state | checked_in: checked_in, checked_out: checked_out, checkout_time: checkout_time}}
  end

  # No error checking; must be done upstream.
  defp check_in(name, pid, state) do
    %{checked_in: checked_in, checked_out: checked_out, checkout_time: checkout_time} = state

    :telemetry.execute(
      [:connection_pool, :checkout, :duration],
      %{usec: monotonic_time() - checkout_time[name]},
      %{conn: name}
    )

    checked_in = [name | checked_in]
    checked_out = if MapSet.size(checked_out[pid]) == 1 do
      Map.delete(checked_out, pid)
    else
      Map.update!(checked_out, pid, &MapSet.delete(&1, name))
    end
    checkout_time = Map.delete(checkout_time, name)

    %{state | checked_in: checked_in, checked_out: checked_out, checkout_time: checkout_time}
  end

  defp ensure_started(name, state) do
    %{started: started, module: module, config: config} = state

    if name in started do
      {:ok, state}
    else
      DynamicSupervisor.start_child(__MODULE__, %{
        id: {__MODULE__, module}, # I don't think ids need to be unique with DynamicSupervisor.
        start: config.start.(name)
      })
      |> case do
        {:ok, _pid} -> {:ok, %{state | started: MapSet.put(started, name)}}
        error -> error
      end
    end
  end

  defp add_waiter(from, opts, state) do
    %{config: config, waiting: waiting} = state

    timer = case opts[:timeout] || config.timeout do
      :infinity -> nil
      n -> Process.send_after(self(), {:checkout_timeout, from}, n)
    end

    waiting = :ordsets.add_element({monotonic_time(), from, timer}, waiting)

    %{state | waiting: waiting}
  end

  defp reply_to_waiter(name, state) do
    reply_to_waiter(name, state.waiting, state)
  end

  # No waiters, or all our waiters already timed out.
  defp reply_to_waiter(_name, [], state) do
    %{state | waiting: :ordsets.new()}
  end

  # The waiter specified timeout: :inifinity, thus they have no timer.
  defp reply_to_waiter(name, [{_time, from, nil} | waiting], state) do
    do_reply(name, from, waiting, state)
  end

  # Waiter has a timer, but it might have expired already.
  defp reply_to_waiter(name, [{_time, from, timer} | waiting], state) do
    case Process.cancel_timer(timer) do
      n when is_integer(n) -> do_reply(name, from, waiting, state)
      false -> reply_to_waiter(name, waiting, state)
    end
  end

  defp do_reply(name, {pid, _ref} = from, waiting, state) do
    {^name, state} = check_out(pid, state)
    :ok = GenServer.reply(from, {:ok, name})
    %{state | waiting: waiting}
  end

  defp monotonic_time do
    System.monotonic_time(:microsecond)
  end

end
