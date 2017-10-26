defmodule Faktory.Connection do
  use Connection
  require Logger

  @default_timeout 4000

  def start_link(config) do
    Connection.start_link(__MODULE__, config)
  end

  def send(conn, data) do
    Connection.call(conn, {:send, data})
  end

  def recv(conn, size \\ :line) do
    Connection.call(conn, {:recv, size})
  end

  def close(conn) do
    Connection.call(conn, :close)
  end

  def init(config) do
    state = Map.put(config, :socket, nil)
    {:connect, :init, state}
  end

  def connect(:init, state) do
    %{host: host, port: port} = state
    host = String.to_charlist(host)
    case :gen_tcp.connect(host, port, [:binary, active: false], @default_timeout) do
      {:ok, socket} ->
        handshake!(socket, state.wid)
        {:ok, %{state | socket: socket}}
      {:error, error} ->
        Logger.warn("Connection failed to #{host}:#{port} (#{error})")
        {:backoff, 1000, state}
    end
  end

  def connect(_, state) do
    case connect(:init, state) do
      {:ok, _} = retval ->
        %{host: host, port: port} = state
        Logger.info("Connection restablished to #{host}:#{port}")
        retval
      retval -> retval
    end
  end

  def disconnect(info, state) do
    # Pull out variables.
    %{socket: socket, host: host, port: port} = state

    # Close the damn thing.
    :ok = :gen_tcp.close(socket)

    case info do
      # Terminate normally.
      {:close, from} ->
        Connection.reply(from, :ok)
        {:stop, :normal, %{state | socket: nil}}
      # Reconnect.
      {:error, :closed} ->
        Logger.warn("Connection closed to #{host}:#{port}")
        {:connect, :reconnect, %{state | socket: nil}}
      # Reconnect.
      {:error, reason} ->
        reason = :inet.format_error(reason)
        Logger.warn("Connection error on #{host}:#{port} (#{reason})")
        {:connect, :reconnect, %{state | socket: nil}}
    end
  end

  def handle_call(_, _, %{socket: nil} = state) do
    {:reply, {:error, :closed}, state}
  end

  def handle_call(:close, from, state) do
    {:disconnect, {:close, from}, state}
  end

  def handle_call({:send, data}, _from, %{socket: socket} = state) do
    case :gen_tcp.send(socket, data) do
      :ok -> {:reply, :ok, state}
      {:error, _} = error -> {:disconnect, error, error, state}
    end
  end

  def handle_call({:recv, size}, _, %{socket: socket} = state) do
    size = setup_size(socket, size)

    case :gen_tcp.recv(socket, size, @default_timeout) do
      {:ok, data} ->
        data = cleanup_data(data, size)
        {:reply, {:ok, data}, state}
      {:error, :timeout} = timeout ->
        {:reply, timeout, state}
      {:error, _} = error ->
        {:disconnect, error, error, state}
    end
  end

  defp handshake!(socket, wid) do
    :inet.setopts(socket, packet: :line)
    {:ok, <<"+HI", rest::binary>>} = :gen_tcp.recv(socket, 0)

    payload = %{
      wid: wid,
      hostname: hostname(),
      pid: System.get_pid |> String.to_integer,
      labels: ["elixir"]
    } |> Poison.encode!

    :ok = :gen_tcp.send(socket, "HELLO #{payload}\r\n")
    {:ok, "+OK\r\n"} = :gen_tcp.recv(socket, 0)
  end

  # If asking for a line, then go into line mode and get whole line.
  defp setup_size(socket, :line) do
    :inet.setopts(socket, packet: :line)
    0
  end

  # Asking for a specified number of bytes.
  defp setup_size(socket, n) do
    :inet.setopts(socket, packet: :raw)
    n
  end

  # If size is 0, then we requested a whole line, so we chomp it.
  defp cleanup_data(data, 0), do: String.replace_suffix(data, "\r\n", "")
  defp cleanup_data(data, _), do: data

  defp hostname do
    {:ok, hostname} = :inet.gethostname
    to_string(hostname)
  end

end
