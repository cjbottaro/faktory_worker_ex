defmodule Faktory.Client do
  @not_connected "not_connected"

  @moduledoc """
  Low level client connection to a Faktory server.

  You shouldn't really need to use this directly, but it can useful for raw
  pushes, getting server info, and using the mutate API.

  ## Quickstart
  ```
  {ok, client} = Faktory.Client.start_link()
  {:ok, info} = Faktory.Client.info(client)
  {:ok, job} = Faktory.Client.push(client, jobtype: "Some::Ruby::Class", args: [1, 2])
  ```

  ## Features

  This module uses the awesome `Connection` library in addition to "active"
  socket connections. This means that connections are _proactively_ reconnected
  on disconnection, even if they are completely idle. This is in contrast to
  passive connections that require some kind of usage to detect a disconnection.

  You can see this in action by making a connection to the Faktory server, then
  restarting the server.
  ```
  {:ok, conn} = Faktory.Client.start_link()

  15:04:31.727 [debug] Connection established to localhost:7419 in 43ms

  {:ok, #PID<0.231.0>}

  # Restart Faktory server

  15:04:40.689 [warn]  Disconnected from localhost:7419 (tcp_closed)

  15:04:40.693 [warn]  Connection failed to localhost:7419 (closed), down for 4ms

  15:04:41.695 [warn]  Connection failed to localhost:7419 (econnrefused), down for 1006ms

  15:04:42.696 [warn]  Connection failed to localhost:7419 (econnrefused), down for 2007ms

  {:error, #{inspect @not_connected}} = Faktory.Client.info(conn)

  15:04:43.698 [warn]  Connection failed to localhost:7419 (econnrefused), down for 3009ms

  15:04:44.699 [warn]  Connection failed to localhost:7419 (econnrefused), down for 4010ms

  15:04:45.700 [warn]  Connection failed to localhost:7419 (econnrefused), down for 5011ms

  15:04:46.701 [warn]  Connection failed to localhost:7419 (econnrefused), down for 6012ms

  15:04:47.714 [info]  Connection reestablished to localhost:7419 in 7026ms

  {:ok, info} = Faktory.Client.info(conn)
  ```

  ## Caveats

  The Faktory server answers requests in the order it receives them. This means if you
  share a single `Faktory.Client` connection between several processes, responses are
  serialized. This is very evident if you call `fetch/2` which can take up to 2 seconds
  to get a response.
  ```
  {ok, conn} = Faktory.Client.start_link()
  Task.start(fn -> Faktory.Client.fetch(conn, "foobar") |> IO.inspect() end)
  Process.sleep(10)
  Faktory.Client.info(conn)

  15:17:42.549 [debug] fetch executed in 2038ms
  {:ok, nil}

  15:17:42.560 [debug] info executed in 2038ms
  {:ok, ...}
  ```

  In other words, the `info/1` call had to wait for the `fetch/2` to finish.

  Consider using `Faktory.Client.Pool` to get around this problem.
  """

  use Connection
  require Logger
  alias Faktory.{Socket, Protocol, Resp}

  def info(client) do
    case Connection.call(client, :info) do
      {:ok, info} -> {:ok, Jason.decode!(info)}
      error -> error
    end
  end

  def push(client, job, _opts \\ []) do
    job = Faktory.Job.new(job)
    case Connection.call(client, {:push, job}) do
      :ok -> {:ok, job}
      error -> error
    end
  end

  def fetch(client, queues, opts \\ [])

  def fetch(client, queues, opts) when is_list(queues) do
    fetch(client, Enum.join(queues, " "), opts)
  end

  def fetch(client, queues, _opts) when is_binary(queues) do
    case Connection.call(client, {:fetch, queues}) do
      {:ok, job} when is_binary(job) -> {:ok, Faktory.Job.new(job)}
      result -> result
    end
  end

  def ack(client, jid) when is_binary(jid) do
    Connection.call(client, {:ack, jid})
  end

  def fail(client, jid, errtype, message, backtrace \\ []) do
    Connection.call(client, {:fail, jid, errtype, message, backtrace})
  end

  def flush(client) do
    Connection.call(client, :flush)
  end

  def beat(client) do
    case Connection.call(client, :beat) do
      {:ok, "OK"} -> :ok
      {:ok, json} -> {:ok, Jason.decode!(json)}
      error -> error
    end
  end

  @doc false
  def crash(client) do
    Connection.cast(client, :crash)
  end

  @defaults [
    host: "localhost",
    port: 7419,
    password: nil,
    tls: false,
    wid: nil,
  ]


  def defaults do
    defaults = Application.get_application(__MODULE__)
    |> Application.get_env(__MODULE__, [])

    Keyword.merge(@defaults, defaults)
  end

  def start_link(config \\ [], opts \\ []) do
    config = Keyword.merge(defaults(), config)

    config = if Keyword.has_key?(config, :use_tls) do
      Logger.warn(":use_tls is deprecated, use :tls instead")
      {use_tls, config} = Keyword.pop!(config, :use_tls)
      Keyword.put(config, :tls, use_tls)
    else
      config
    end

    Connection.start_link(__MODULE__, config, opts)
  end

  def init(config) do
    state = %{
      config: Map.new(config),
      socket: nil,
      greeting: nil,
      connecting_at: System.monotonic_time(:microsecond),
      disconnected: false,
      calls: :queue.new(),
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
      [:faktory, :client, :connection, :disconnect],
      %{},
      %{config: state.config, reason: reason}
    )

    # Update our state.
    state = %{state |
      socket: nil,
      connecting_at: System.monotonic_time(:microsecond),
      disconnected: true
    }

    # Try to reconnect immediately.
    {:connect, :backoff, state}
  end

  def handle_info({:tcp, socket, line}, state) when state.socket == socket do
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

        :beat -> reply(from, {:ok, result})

      end
    end

    :telemetry.execute(
      [:faktory, :client, :call, call],
      %{usec: System.monotonic_time(:microsecond) - at},
      %{result: result}
    )

    :ok = Socket.active(socket, :once)

    {:noreply, state}
  end

  def handle_info({:tcp_closed, socket}, state) when state.socket == socket do
    {:disconnect, :tcp_closed, state}
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

  def handle_call(:beat, from, state) do
    Socket.send(state.socket, Protocol.beat(state.config.wid))
    {:noreply, push_call(from, :beat, state)}
  end

  def handle_call(:flush, from, state) do
    Socket.send(state.socket, Protocol.flush())
    {:noreply, push_call(from, :flush, state)}
  end

  def handle_cast(:crash, _state) do
    raise "crash"
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
          [:faktory, :client, :connection, :success],
          %{usec: System.monotonic_time(:microsecond) - state.connecting_at},
          %{config: state.config, disconnected: state.disconnected}
        )
        {:ok, %{state | socket: socket, greeting: greeting}}

      {:error, reason} ->
        :telemetry.execute(
          [:faktory, :client, :connection, :failure],
          %{usec: System.monotonic_time(:microsecond) - state.connecting_at},
          %{config: state.config, reason: reason}
        )
        {:backoff, 1000, state}
    end
  end

  defp connect_and_handshake(state) do
    %{host: host, port: port} = state.config

    opts = [:binary, active: false, packet: :line]
    with {:ok, socket} <- Socket.connect(host, port, opts),
      {:ok, <<"HI", greeting::binary>>} <- Resp.recv(socket),
      {:ok, greeting} <- Jason.decode(greeting),
      hello = Protocol.hello(greeting, state.config),
      :ok <- Socket.send(socket, hello),
      {:ok, "OK"} <- Resp.recv(socket),
      :ok <- Socket.active(socket, :once)
    do
      {:ok, socket, greeting}
    end
  end

end
