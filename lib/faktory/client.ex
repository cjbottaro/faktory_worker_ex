defmodule Faktory.Client do
  use Connection
  require Logger
  alias Faktory.{Socket, Protocol, Resp}

  @not_connected "not_connected"

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
