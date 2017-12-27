defmodule Faktory.Connection do
  @moduledoc false
  use Connection
  alias Faktory.Logger

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
    state = config |> Map.put(:socket, nil) |> Map.put(:transport, nil)
    {:connect, :init, state}
  end

  def connect(:init, state) do
    %{host: host, port: port, use_tls: use_tls} = state
    host = String.to_charlist(host)
    transport = if use_tls, do: :ssl, else: :gen_tcp

    base_opts = [:binary, active: false]
    tcp_opts = if use_tls do
      # Disable TLS verification in dev/test so that self-signed certs will work
      verify_opts = if Mix.env in [:dev, :test], do: [verify: :verify_none], else: [verify: :verify_peer]
      base_opts ++ verify_opts ++ [versions: [:'tlsv1.2']]
    else
      base_opts
    end

    case transport.connect(host, port, tcp_opts, @default_timeout) do
      {:ok, socket} ->
        handshake!(transport, socket, state.wid)
        {:ok, %{state | socket: socket, transport: transport}}
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
    :ok = state.transport.close(socket)

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
    case state.transport.send(socket, data) do
      :ok -> {:reply, :ok, state}
      {:error, _} = error -> {:disconnect, error, error, state}
    end
  end

  def handle_call({:recv, size}, _, %{socket: socket, transport: transport} = state) do
    size = setup_size(transport, socket, size)

    case state.transport.recv(socket, size, @default_timeout) do
      {:ok, data} ->
        data = cleanup_data(data, size)
        {:reply, {:ok, data}, state}
      {:error, :timeout} = timeout ->
        {:reply, timeout, state}
      {:error, _} = error ->
        {:disconnect, error, error, state}
    end
  end

  defp handshake!(transport, socket, wid) do
    setup_size(transport, socket, :line)
    {:ok, <<"+HI", _rest::binary>>} = transport.recv(socket, 0)

    payload = %{
      wid: wid,
      hostname: hostname(),
      pid: System.get_pid |> String.to_integer,
      labels: ["elixir"]
    } |> Poison.encode!

    :ok = transport.send(socket, "HELLO #{payload}\r\n")
    {:ok, "+OK\r\n"} = transport.recv(socket, 0)
  end

  # If asking for a line, then go into line mode and get whole line.
  defp setup_size(transport, socket, :line) do
    setopts_mod(transport).setopts(socket, packet: :line)
    0
  end

  # Asking for a specified number of bytes.
  defp setup_size(transport, socket, n) do
    setopts_mod(transport).setopts(socket, packet: :raw)
    n
  end

  # If size is 0, then we requested a whole line, so we chomp it.
  defp cleanup_data(data, 0), do: String.replace_suffix(data, "\r\n", "")
  defp cleanup_data(data, _), do: data

  defp hostname do
    {:ok, hostname} = :inet.gethostname
    to_string(hostname)
  end

  defp setopts_mod(transport) do
    case transport do
      :ssl -> :ssl
      :gen_tcp -> :inet
    end
  end

end
