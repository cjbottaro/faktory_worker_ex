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
    config = Map.new(config)

    # Aid testing.
    Map.get(config, :on_init, fn -> nil end).()

    config
    |> Map.put_new(:socket_impl, Faktory.Socket)
    |> Map.put(:socket, nil)
    |> do_connect
  end

  def connect(:backoff, state), do: do_connect(state)

  def disconnect(info, state) do
    # Pull out variables.
    %{host: host, port: port} = state

    # Close the damn thing.
    :ok = socket_close(state)

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

  def handle_call({:send, data}, _from, state) do
    case socket_send(state, data) do
      :ok -> {:reply, :ok, state}
      {:error, _} = error -> {:disconnect, error, error, state}
    end
  end

  def handle_call({:recv, size}, _, state) do
    case socket_recv(state, size, timeout: @default_timeout) do
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
    %{host: host, port: port} = state

    uri = case state.use_tls do
      false -> "tcp://#{host}:#{port}"
      true -> "ssl://#{host}:#{port}"
    end

    case socket_connect(state, uri) do
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

    {:ok, <<"+HI", rest::binary>>} = socket_recv(state, :line)

    server_config = Poison.decode!(rest)
    server_version = server_config["v"]

    if server_version > 2 do
      Logger.warn("Warning: Faktory server protocol #{server_version} in use, but this worker doesn't speak that version")
    end

    password_opts = password_opts(state.password, server_config)

    payload = %{
      hostname: Utils.hostname,
      pid: Utils.unix_pid,
      labels: ["elixir"],
      v: 2,
    }
    |> add_wid(state) # Client connection don't have wid
    |> Map.merge(password_opts)
    |> Poison.encode!

    :ok = socket_send(state, "HELLO #{payload}\r\n")
    {:ok, "+OK\r\n"} = socket_recv(state, :line)
  end

  defp add_wid(payload, %{wid: wid}), do: Map.put(payload, :wid, wid)
  defp add_wid(payload, _), do: payload

  defp password_opts(nil, %{"s" => _salt}), do: raise "This server requires a password, but a password hasn't been configured"

  defp password_opts(password, %{"s" => salt, "i" => iterations}) do
    %{pwdhash: Faktory.Utils.hash_password(iterations, password, salt)}
  end

  defp password_opts(_password, _server_config), do: %{}

  # If size is :line, then we requested a whole line, so we chomp it.
  defp cleanup_data(data, :line), do: String.replace_suffix(data, "\r\n", "")
  defp cleanup_data(data, _), do: data

  defp socket_connect(state, uri) do
    state.socket_impl.connect(uri)
  end

  defp socket_close(state) do
    state.socket_impl.close(state.socket)
  end

  defp socket_send(state, data) do
    state.socket_impl.send(state.socket, data)
  end

  defp socket_recv(state, size, options \\ []) do
    state.socket_impl.recv(state.socket, size, options)
  end

end
