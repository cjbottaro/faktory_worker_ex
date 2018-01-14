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
    Map.get(config, :on_init, fn -> nil end).() # Aid testing.

    config
      |> Map.put(:socket, nil)
      |> Map.put_new(:tcp, Faktory.Tcp)
      |> do_connect
  end

  def connect(:backoff, state), do: do_connect(state)

  def disconnect(info, state) do
    # Pull out variables.
    %{tcp: tcp, socket: socket, host: host, port: port} = state

    # Close the damn thing.
    :ok = tcp.close(socket)

    case info do
      # Terminate normally.
      {:close, from} ->
        Connection.reply(from, :ok)
        {:stop, :normal, %{state | socket: nil}}
      # Reconnect.
      {:error, :closed} ->
        Logger.warn("Connection closed to #{host}:#{port}")
        {:connect, :backoff, %{state | socket: nil}}
      # Reconnect.
      {:error, reason} ->
        reason = :inet.format_error(reason)
        Logger.warn("Connection error on #{host}:#{port} (#{reason})")
        {:connect, :backoff, %{state | socket: nil}}
    end
  end

  def handle_call(_, _, %{socket: nil} = state) do
    {:reply, {:error, :closed}, state}
  end

  def handle_call(:close, from, state) do
    {:disconnect, {:close, from}, state}
  end

  def handle_call({:send, data}, _from, %{tcp: tcp, socket: socket} = state) do
    case tcp.send(socket, data) do
      :ok -> {:reply, :ok, state}
      {:error, _} = error -> {:disconnect, error, error, state}
    end
  end

  def handle_call({:recv, size}, _, %{tcp: tcp, socket: socket} = state) do
    size = tcp.setup_size(socket, size)

    case tcp.recv(socket, size, @default_timeout) do
      {:ok, data} ->
        data = cleanup_data(data, size)
        {:reply, {:ok, data}, state}
      {:error, :timeout} = timeout ->
        {:reply, timeout, state}
      {:error, _} = error ->
        {:disconnect, error, error, state}
    end
  end

  defp do_connect(state) do
    %{host: host, port: port, tcp: tcp} = state

    case tcp.connect(state) do
      {:ok, socket} ->
        state = %{state | socket: socket}
        handshake!(state)
        %{host: host, port: port} = state
        Logger.info("Connection established to #{host}:#{port}")
        {:ok, state}
      {:error, error} ->
        Logger.warn("Connection failed to #{host}:#{port} (#{error})")
        {:backoff, 1000, state}
    end
  end

  defp handshake!(state) do
    alias Faktory.Utils

    %{tcp: tcp, socket: socket, wid: wid, password: password} = state

    tcp.setup_size(socket, :line)
    {:ok, <<"+HI", rest::binary>>} = tcp.recv(socket, 0)

    server_config = Poison.decode!(rest)
    server_version = server_config["v"]

    if server_version > 2 do
      Logger.warn("Warning: Faktory server protocol #{server_version} in use, but this worker doesn't speak that version")
    end

    payload = %{
      wid: wid,
      hostname: Utils.hostname,
      pid: Utils.unix_pid,
      labels: ["elixir"],
      v: 2,
    }
    |> Map.merge(password_opts(password, server_config))
    |> Poison.encode!

    :ok = tcp.send(socket, "HELLO #{payload}\r\n")
    {:ok, "+OK\r\n"} = tcp.recv(socket, 0)
  end

  defp password_opts(nil, %{"s" => _salt}), do: raise "This server requires a password, but a password hasn't been configured"

  defp password_opts(password, %{"s" => salt, "i" => iterations}) do
    %{pwdhash: Faktory.Utils.hash_password(iterations, password, salt)}
  end

  defp password_opts(_password, _server_config), do: %{}

  # If size is 0, then we requested a whole line, so we chomp it.
  defp cleanup_data(data, 0), do: String.replace_suffix(data, "\r\n", "")
  defp cleanup_data(data, _), do: data

end
