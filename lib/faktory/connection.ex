defmodule Faktory.Connection do
  @moduledoc false
  use Connection
  alias Faktory.Logger
  import Faktory.Utils, only: [if_test: 1]
  import Kernel, except: [send: 2]

  @default_timeout 4000

  # This is a hidden option for myself. When my laptop goes to sleep,
  # it causes my entire worker supervision tree to crash. I tracked it
  # down to a recv timing out (Connection.call) in the fetcher stage.
  # raising this to something like 10_000 fixes the problem.
  @connection_call_timeout Faktory.get_env(:connection_call_timeout, 5000)

  def start_link(config) do
    Connection.start_link(__MODULE__, config)
  end

  def send(conn, data) when is_pid(conn) do
    Connection.call(conn, {:send, data})
  end

  def send(state, data) when is_map(state) do
    socket_send(state, data)
  end

  def recv(conn, size) when is_pid(conn) do
    Connection.call(conn, {:recv, size}, @connection_call_timeout)
  end

  def recv(state, size, options \\ []) when is_map(state) do
    socket_recv(state, size, options)
  end

  def close(conn) do
    Connection.call(conn, :close)
  end

  def init(config) do
    config = Map.new(config)

    state = config
    |> Map.put_new(:socket_impl, Faktory.Socket)
    |> Map.put_new(:use_tls, false)
    |> Map.put_new(:password, nil)
    |> Map.put(:socket, nil)

    # Aid testing.
    if_test do: state[:on_init] && state[:on_init].()

    {:connect, :init, state}
  end

  def connect(context, state) do
    with \
      {:ok, socket} <- socket_connect(state),
      state = %{state | socket: socket},
      {:ok, server} <- Faktory.Protocol.handshake(state, hello(state))
    do
      if server["v"] > 2 do
        Logger.warn("Server protocol version higher than supported")
      end
      log_connect(context, state)
      if_test do: state[:on_connect] && state[:on_connect].()
      {:ok, state}
    else
      {:error, reason} ->
        %{host: host, port: port} = state
        reason = :inet.format_error(reason)
        Logger.warn("Connection failed to #{host}:#{port} (#{reason})")
        {:backoff, 1000, state}
    end
  end

  def disconnect(info, state) do
    # Pull out variables.
    %{host: host, port: port} = state

    # Close the damn thing.
    :ok = socket_close(state)

    # Remove socket from state.
    state = %{state | socket: nil}

    case info do
      # Terminate normally.
      {:close, from} ->
        Connection.reply(from, :ok)
        {:stop, :normal, %{state | socket: nil}}
      # Reconnect.
      {:error, reason} ->
        reason = :inet.format_error(reason)
        Logger.warn("Disconnected #{host}:#{port} (#{reason})")
        {:connect, :backoff, %{state | socket: nil}}
    end
  end

  def handle_call(_msg, _from, %{socket: nil} = state) do
    {:reply, {:error, :closed}, state}
  end

  def handle_call(:close, from, state) do
    {:disconnect, {:close, from}, state}
  end

  def handle_call({:send, data}, _from, state) do
    case send(state, data) do
      :ok -> {:reply, :ok, state}
      {:error, _} = error -> {:disconnect, error, error, state}
    end
  end

  def handle_call({:recv, size}, _, state) do
    case recv(state, size, timeout: @default_timeout) do
      {:ok, _data} = result -> {:reply, result, state}
      {:error, :timeout} = timeout -> {:reply, timeout, state}
      {:error, _reason} = error -> {:disconnect, error, error, state}
    end
  end

  defp hello(state) do
    alias Faktory.Utils
    %{
      password: state.password,
      hostname: Utils.hostname,
      pid: Utils.unix_pid,
      labels: ["elixir"],
      v: 2,
    }
    |> add_wid(state) # Client connection don't have wid
  end

  defp add_wid(payload, %{wid: wid}), do: Map.put(payload, :wid, wid)
  defp add_wid(payload, _), do: payload

  defp socket_connect(state) do
    %{socket_impl: socket_impl, host: host, port: port, use_tls: use_tls} = state
    case use_tls do
      true -> socket_impl.connect("ssl://#{host}:#{port}")
      false -> socket_impl.connect("tcp://#{host}:#{port}")
    end
  end

  defp socket_close(state) do
    state.socket_impl.close(state.socket)
  end

  defp socket_send(state, data) do
    state.socket_impl.send(state.socket, chomp(data) <> "\r\n")
  end

  defp socket_recv(state, size, options)

  defp socket_recv(state, :line, options) do
    case state.socket_impl.recv(state.socket, :line, options) do
      {:ok, line} -> {:ok, chomp(line)}
      error -> error
    end
  end

  defp socket_recv(state, size, options) do
    state.socket_impl.recv(state.socket, size, options)
  end

  defp log_connect(:init, %{host: host, port: port}) do
    Logger.debug "Connection established to #{host}:#{port}"
  end

  defp log_connect(context, %{host: host, port: port}) do
    Logger.info  "Connection reestablished to #{host}:#{port} (#{context})"
  end

  defp chomp(string), do: String.replace_suffix(string, "\r\n", "")

end
