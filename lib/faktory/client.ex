defmodule Faktory.Client do
  use Connection
  require Logger
  alias Faktory.{Socket, Protocol, Resp}

  @not_connected "not_connected"

  def info(client) do
    Connection.call(client, :info)
  end

  def push(client, job, opts \\ [])

  def push(client, job, opts) when is_list(job) do
    push(client, Map.new(job), opts)
  end

  def push(_client, _jobs, opts) when not is_list(opts) do
    raise ArgumentError, "expecting keyword list, got #{inspect opts}"
  end

  def push(client, job, _opts) do\
    job = Map.new(job, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
      {k, v} when is_atom(k) -> {k, v}
      {k, _v} -> raise ArgumentError, "expecting strings or atoms for job keys, got: #{inspect k}"
    end)
    Connection.call(client, {:push, job})
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
      requests: [],
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

    # Any pending requests need to fail.
    Enum.each(state.requests, &GenServer.reply(&1, {:error, @not_connected}))

    # Update our state.
    state = %{state |
      socket: nil,
      connecting_at: System.monotonic_time(:microsecond),
      disconnected: true,
      requests: []
    }

    # Try to reconnect immediately.
    {:connect, :backoff, state}
  end

  def handle_info({:tcp_closed, socket}, state) when state.socket == socket do
    {:disconnect, :tcp_closed, state}
  end

  def handle_call(_, _, %{socket: nil} = state) do
    {:reply, {:error, @not_connected}, state}
  end

  def handle_call(:info, _from, state) do
    %{socket: socket} = state

    with :ok <- Socket.active(socket, false),
      :ok <- Socket.send(socket, Protocol.info()),
      {:ok, payload} <- Resp.recv(socket),
      :ok <- Socket.active(socket, :once)
    do
      {:reply, {:ok, Jason.decode!(payload)}, state}
    end
  end

  def handle_call({:push, job}, _from, state) do
    %{socket: socket} = state

    with :ok <- Socket.active(socket, false),
      :ok <- Socket.send(socket, Protocol.push(job)),
      {:ok, "OK"} <- Resp.recv(socket)
    do
      {:reply, {:ok, job}, state}
    end
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
