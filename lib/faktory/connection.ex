defmodule Faktory.Connection do
  @not_connected :not_connected

  @moduledoc """
  Low level connection to a Faktory server.

  You shouldn't really need to use this directly (other than configuring it);
  use `Faktory.Client` instead.

  ## Default configuration

  You can override the default options that are used by `start_link/1` via
  `Config`.

  ```
  config :faktory_worker_ex, Faktory.Connection,
    host: "faktory.myapp.com"
  ```

  Now _all_ connections will default to using `host: "faktory.myapp.com"`, even
  ones used internally by `Faktory.Worker`.

  ## Automatic reconnection

  This module uses the awesome `Connection` library in addition to "active"
  socket connections. This means that connections are _proactively_ reconnected
  on disconnection, even if they are completely idle. This is in contrast to
  passive connections that require some kind of usage to detect a disconnection.

  You can see this in action by making a connection to the Faktory server, then
  restarting the server.
  ```
  {:ok, conn} = Faktory.Connection.start_link()

  15:04:31.727 [debug] Connection established to localhost:7419 in 43ms

  {:ok, #PID<0.231.0>}

  # Restart Faktory server

  15:04:40.689 [warn]  Disconnected from localhost:7419 (tcp_closed)

  15:04:40.693 [warn]  Connection failed to localhost:7419 (closed), down for 4ms

  15:04:41.695 [warn]  Connection failed to localhost:7419 (econnrefused), down for 1006ms

  15:04:42.696 [warn]  Connection failed to localhost:7419 (econnrefused), down for 2007ms

  {:error, #{inspect @not_connected}} = Faktory.Connection.info(conn)

  15:04:43.698 [warn]  Connection failed to localhost:7419 (econnrefused), down for 3009ms

  15:04:44.699 [warn]  Connection failed to localhost:7419 (econnrefused), down for 4010ms

  15:04:45.700 [warn]  Connection failed to localhost:7419 (econnrefused), down for 5011ms

  15:04:46.701 [warn]  Connection failed to localhost:7419 (econnrefused), down for 6012ms

  15:04:47.714 [info]  Connection reestablished to localhost:7419 in 7026ms

  {:ok, info} = Faktory.Connection.info(conn)
  ```

  ## Caveats

  The Faktory server answers requests in the order it receives them. This means
  if you share a single `Faktory.Connection` connection between several
  processes, responses are serialized. This is very evident if you call
  `fetch/2` which can take up to 2 seconds to get a response.
  ```
  {ok, conn} = Faktory.Connection.start_link()
  Task.start(fn -> Faktory.Connection.fetch(conn, "foobar") |> IO.inspect() end)
  Process.sleep(10)
  Faktory.Connection.info(conn)

  15:17:42.549 [debug] fetch executed in 2038ms
  {:ok, nil}

  15:17:42.560 [debug] info executed in 2038ms
  {:ok, ...}
  ```

  In other words, the `info/1` call had to wait for the `fetch/2` to finish.

  To get around this problem, use `Faktory.Client` which is a pool of
  connections.
  """

  @type t :: GenServer.server()

  @type mutation :: Keyword.t | %{
    required(:cmd) => binary,
    required(:target) => binary,
    required(:filter) => mutation_filter
  }

  @type mutation_filter :: Keyword.t | %{
    optional(:jobtype) => binary,
    optional(:jids) => [binary],
    optional(:regex) => binary
  }

  use Connection
  require Logger
  alias Faktory.{Socket, Protocol, Resp}

  @beat_interval 15_000

  @defaults [
    host: "localhost",
    port: 7419,
    password: nil,
    tls: false,
    wid: nil,
    beat_receiver: nil,
  ]

  @doc """
  Default configuration.

  ```
  #{inspect @defaults, pretty: true, width: 0}
  ```
  """
  def defaults do
    @defaults
  end

  @doc """
  Configuration from `Config`.

  The options specified with `Config` will be merged with `defaults/0`.

  ```
  config :faktory_worker_ex, #{inspect __MODULE__}, host: "foo.bar.com"

  iex(1)> #{inspect __MODULE__}.config()
  #{inspect Keyword.merge(@defaults, host: "foo.bar.com"), pretty: true, width: 0}
  ```
  """
  def config do
    config = Application.get_application(__MODULE__)
    |> Application.get_env(__MODULE__, [])

    Keyword.merge(@defaults, config)
  end

  @doc """
  Start up a connection.

  The `config` argument is merged over `config/0`.

  ## Options

  * `:host` (binary) hostname or ip address
  * `:port` (integer) port
  * `:password` (binary) if the server requires a password
  * `:tls` (boolean) if the server uses TLS
  * `:wid` (binary) Unique worker id
  * `:name` (`t:GenServer.name/0`) Name registration
  * `:beat_receiver` (pid) Send messages to pid on state change.

  ## Worker mode

  If `:wid` is provided, then the connection is started up in worker mode and
  will periodically send heartbeats to the Faktory server. This will make the
  connection show up in the Faktory UI as a worker process.

  ## Examples

  ```
  {:ok, conn} = Faktory.Connection.start_link()
  {:ok, conn} = Faktory.Connection.start_link(host: "foo.bar.com", name: MyConn)
  ```
  """
  def start_link(config \\ []) do
    config = Keyword.merge(config(), config)

    config = if Keyword.has_key?(config, :use_tls) do
      Logger.warn(":use_tls is deprecated, use :tls instead")
      {use_tls, config} = Keyword.pop!(config, :use_tls)
      Keyword.put(config, :tls, use_tls)
    else
      config
    end

    {config, gen_opts} = Keyword.split(config, Keyword.keys(@defaults))

    Connection.start_link(__MODULE__, config, gen_opts)
  end

  @doc """
  Get Faktory server info.

  ```
  {:ok, info} = #{inspect __MODULE__}.info(conn)
  ```
  """
  @spec info(t) :: {:ok, map} | {:error, term}
  def info(conn) do
    case Connection.call(conn, :info) do
      {:ok, info} -> {:ok, Jason.decode!(info)}
      error -> error
    end
  end

  @doc """
  Enqueue a job.

  See `t:Faktory.push_job/0` for what constitutes the `job` argument.

  ## Options

  * `:middleware` (atom) run specified middleware on the job

  ## Examples
  ```
  {:ok, job} = #{inspect __MODULE__}.push(conn, jobtype: "MyJob", queue: "some-queue")

  iex(1)> job.jid
  "#{Faktory.Utils.new_jid()}"

  job = [jobtype: "MyJob", queue: "queue-one"]
  {:ok, job} = #{inspect __MODULE__}.push(conn, [middleware: MyMiddleware], job)

  iex(1)> job.queue
  "queue-two"
  ```
  """
  @spec push(t, Faktory.push_job) :: {:ok, Faktory.push_job} | {:error, term}
  def push(conn, job) do
    job = Faktory.Job.new(job)
    case Connection.call(conn, {:push, job}) do
      :ok -> {:ok, job}
      error -> error
    end
  end

  @doc """
  Fetch a job from the server.

  If there are no jobs on the server, this function will block up to two seconds
  for one.

  If the connection was "quieted" or "stopped" from the Faktory UI, then this
  function will return either `{:error, :quiet}` or `{:error, :terminate}`
  respectively.

  ```
  {:ok, job} = #{inspect __MODULE__}.fetch(conn, "default")
  {:ok, job} = #{inspect __MODULE__}.fetch(conn, "queue-one queue-two")
  {:ok, job} = #{inspect __MODULE__}.fetch(conn, ["queue-one", "queue-two"])
  ```
  """
  @spec fetch(t, binary | [binary]) ::
    {:ok, Faktory.fetch_job}
    | {:ok, nil}
    | {:error, :quiet}
    | {:error, :terminate}
    | {:error, term}

  def fetch(conn, queues) when is_list(queues) do
    fetch(conn, Enum.join(queues, " "))
  end

  def fetch(conn, queues) when is_binary(queues) do
    case Connection.call(conn, {:fetch, queues}) do
      {:ok, job} when is_binary(job) -> {:ok, Faktory.Job.new(job)}
      result -> result
    end
  end

  @doc """
  Ack a job.

  ```
  :ok = #{inspect __MODULE__}.ack(conn, "#{Faktory.Utils.new_jid()}")
  ```
  """
  @spec ack(t, binary) :: :ok | {:error, term}
  def ack(conn, jid) when is_binary(jid) do
    Connection.call(conn, {:ack, jid})
  end

  @doc """
  Fail a job.

  ```
  :ok = #{inspect __MODULE__}.fail(conn,
    "#{Faktory.Utils.new_jid()}",
    "ArgumentError",
    "bad argument or something",
    stacktrace
  )
  ```
  """
  @spec fail(t, binary, binary, binary, [binary]) :: :ok | {:error, term}
  def fail(conn, jid, errtype, message, backtrace \\ []) do
    Connection.call(conn, {:fail, jid, errtype, message, backtrace})
  end

  @doc """
  Clear Faktory server state.

  ```
  :ok = #{inspect __MODULE__}.flush(conn)
  ```
  """
  @spec flush(t) :: :ok | {:error, term}
  def flush(conn) do
    Connection.call(conn, :flush)
  end

  @doc """
  Mutate API.

  ```
  #{inspect __MODULE__}.mutate(conn,
    cmd: "kill",
    target: "scheduled",
    filter: [
      jobtype: "SomeJob"
      jids: [
        "#{Faktory.Utils.new_jid()}",
        "#{Faktory.Utils.new_jid()}"
      ]
    ]
  )
  ```

  See [Mutate API](https://github.com/contribsys/faktory/wiki/Mutate-API) for more info.
  """
  @spec mutate(t, mutation) :: :ok | {:error, term}
  def mutate(conn, mutation) when is_list(mutation) do
    mutate(conn, Map.new(mutation))
  end

  def mutate(conn, mutation) when is_map(mutation) do
    mutation = Map.update(mutation, :filter, %{}, fn
      filter when is_list(filter) -> Map.new(filter)
      filter when is_map(filter) -> filter
    end)
    Connection.call(conn, {:mutate, mutation})
  end

  def init(config) do
    state = %{
      config: Map.new(config),
      socket: nil,
      greeting: nil,
      connecting_at: System.monotonic_time(:microsecond),
      disconnected: false,
      calls: :queue.new(),
      beat_timer: nil,
      beat_state: nil,
    }

    establish_connection(state)
  end

  def connect(:backoff, state) do
    establish_connection(%{state | disconnected: true})
  end

  def disconnect(reason, state) do
    # Sure why not.
    :ok = Socket.close(state.socket)

    # Logging.
    :telemetry.execute(
      [:faktory, :connection, :disconnect],
      %{},
      %{config: state.config, reason: reason}
    )

    # Update our state.
    state = %{state |
      socket: nil,
      connecting_at: System.monotonic_time(:microsecond),
      disconnected: true
    }

    # Can't heartbeat if not connected.
    if state.beat_timer do
      Process.cancel_timer(state.beat_timer)
    end

    # Try to reconnect immediately.
    {:connect, :backoff, state}
  end

  def handle_info({transport, socket, line}, state) when transport in [:tcp, :ssl] and state.socket == socket do
    {{from, at, call}, state} = pop_call(state)

    :telemetry.execute(
      [:faktory, :socket, :recv],
      %{usec: System.monotonic_time(:microsecond) - at},
      %{result: {:ok, line}}
    )

    result = case Resp.parse(line, socket) do
      {:ok, {:error, reason}} -> {:error, reason} # Translate RESP -ERR errors.
      any -> any
    end

    :ok = Socket.active(socket, :once)

    # Intercept heartbeats.
    if call == :beat do

      handle_beat(result, at, state)

    else

      import Connection, only: [reply: 2]

      case result do
        {:error, reason} -> reply(from, {:error, reason})

        {:ok, result} -> case call do

          :info -> reply(from, {:ok, result})

          :push -> reply(from, :ok)

          :fetch -> reply(from, {:ok, result})

          :ack -> reply(from, :ok)

          :fail -> reply(from, :ok)

          :flush -> reply(from, :ok)

          :mutate -> reply(from, :ok)

        end
      end

      :telemetry.execute(
        [:faktory, :command, call],
        %{usec: System.monotonic_time(:microsecond) - at},
        %{result: result}
      )

      {:noreply, state}

    end
  end

  def handle_info({reason, socket}, state) when reason in [:tcp_closed, :ssl_closed] and state.socket == socket do
    {:disconnect, reason, state}
  end

  def handle_info(:beat, state) do
    Socket.send(state.socket, Protocol.beat(state.config.wid))
    {:noreply, push_call(nil, :beat, state)}
  end

  def handle_beat(result, at, state) do
    %{config: config} = state

    beat_state = case result do
      {:ok, "OK"} -> nil
      {:ok, json} -> Jason.decode!(json) |> Map.fetch!("state") |> String.to_atom()
      {:error, reason} ->
        Logger.error("Heartbeat #{reason}")
        nil
    end

    if beat_state && config.beat_receiver do
      send(config.beat_receiver, {:faktory, :beat, beat_state})
    end

    :telemetry.execute(
      [:faktory, :connection, :heartbeat],
      %{usec: System.monotonic_time(:microsecond) - at},
      %{result: result}
    )

    {:noreply, %{state |
      beat_timer: Process.send_after(self(), :beat, @beat_interval),
      beat_state: beat_state
    }}
  end

  def handle_call(_, _, %{socket: nil} = state) do
    {:reply, {:error, @not_connected}, state}
  end

  def handle_call(:info, from, state) do
    Socket.send(state.socket, Protocol.info())
    {:noreply, push_call(from, :info, state)}
  end

  def handle_call({:push, job}, from, state) do
    Socket.send(state.socket, Protocol.push(job))
    {:noreply, push_call(from, :push, state)}
  end

  def handle_call({:fetch, _queues}, _from, state) when state.beat_state in [:quiet, :terminate] do
    {:reply, {:error, state.beat_state}, state}
  end

  def handle_call({:fetch, queues}, from, state) do
    Socket.send(state.socket, Protocol.fetch(queues))
    {:noreply, push_call(from, :fetch, state)}
  end

  def handle_call({:ack, jid}, from, state) do
    Socket.send(state.socket, Protocol.ack(jid))
    {:noreply, push_call(from, :ack, state)}
  end

  def handle_call({:fail, jid, errtype, message, backtrace}, from, state) do
    Socket.send(state.socket, Protocol.fail(jid, errtype, message, backtrace))
    {:noreply, push_call(from, :fail, state)}
  end

  def handle_call(:flush, from, state) do
    Socket.send(state.socket, Protocol.flush())
    {:noreply, push_call(from, :flush, state)}
  end

  def handle_call({:mutate, mutation}, from, state) do
    Socket.send(state.socket, Protocol.mutate(mutation))
    {:noreply, push_call(from, :mutate, state)}
  end

  defp push_call(from, name, state) do
    %{calls: calls} = state

    item = {
      from,
      System.monotonic_time(:microsecond),
      name
    }

    calls = :queue.in(item, calls)

    %{state | calls: calls}
  end

  defp pop_call(state) do
    %{calls: calls} = state

    {{:value, call}, calls} = :queue.out(calls)

    state = %{state | calls: calls}

    {call, state}
  end

  defp establish_connection(state) do
    case connect_and_handshake(state) do
      {:ok, socket, greeting} ->
        :telemetry.execute(
          [:faktory, :connection, :success],
          %{usec: System.monotonic_time(:microsecond) - state.connecting_at},
          %{config: state.config, disconnected: state.disconnected}
        )
        timer = if state.config.wid do
          Process.send_after(self(), :beat, @beat_interval)
        else
          nil
        end
        {:ok, %{state | socket: socket, greeting: greeting, beat_timer: timer}}

      {:error, reason} ->
        :telemetry.execute(
          [:faktory, :connection, :failure],
          %{usec: System.monotonic_time(:microsecond) - state.connecting_at},
          %{config: state.config, reason: reason}
        )

        case reason do
          "ERR Invalid password" -> {:stop, "Invalid password"}
          _ -> {:backoff, 1000, state}
        end
    end
  end

  defp connect_and_handshake(state) do
    %{host: host, port: port, tls: tls} = state.config

    opts = [:binary, active: false, packet: :line, tls: tls]
    with {:ok, socket} <- Socket.connect(host, port, opts),
      {:ok, <<"HI", greeting::binary>>} <- Resp.recv(socket),
      {:ok, greeting} <- Jason.decode(greeting),
      hello = Protocol.hello(greeting, state.config),
      :ok <- Socket.send(socket, hello),
      {:ok, "OK"} <- Resp.recv(socket),
      :ok <- Socket.active(socket, :once)
    do
      {:ok, socket, greeting}
    else
      {:ok, {:error, reason}} -> {:error, reason}
      error -> error
    end
  end

end
