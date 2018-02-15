defmodule Faktory.Tcp do
  @moduledoc false

  defstruct [:transport, :socket]

  @type tcp_struct :: %__MODULE__{}

  @callback connect(options :: Keyword.t) :: tcp_struct
  @callback close(tcp_struct) :: :ok
  @callback setup_size(tcp_struct, size :: :line | integer) :: 0 | integer
  @callback send(tcp_struct, data :: binary) :: :ok | {:error, reason :: term}
  @callback recv(tcp_struct, size :: integer) :: {:ok, data :: binary} | {:error, reason :: term}
  @callback recv(tcp_struct, size :: integer, timeout :: integer) :: {:ok, data :: binary} | {:error, reason :: term}

  @default_timeout 4000

  def connect(options) do
    %{host: host, port: port, use_tls: use_tls} = options

    real = if use_tls do
      %__MODULE__{transport: :ssl}
    else
      %__MODULE__{transport: :gen_tcp}
    end

    host = String.to_charlist(host)
    tcp_opts = tcp_opts(options)
    timeout = Map.get(options, :timeout, @default_timeout)

    case real.transport.connect(host, port, tcp_opts, timeout) do
      {:ok, socket} -> {:ok, %{real | socket: socket}}
      error -> error
    end
  end

  # Returns :ok
  def close(%{transport: transport, socket: socket}) do
    transport.close(socket)
  end

  # If asking for a line, then go into line mode and get whole line.
  def setup_size(%{transport: transport, socket: socket}, :line) do
    setopts_mod(transport).setopts(socket, packet: :line)
    0
  end

  # Asking for a specified number of bytes.
  def setup_size(%{transport: transport, socket: socket}, n) do
    setopts_mod(transport).setopts(socket, packet: :raw)
    n
  end

  # Returns :ok | {:error, reason}
  def send(%{transport: transport, socket: socket}, data) do
    transport.send(socket, data)
  end

  # Returns {:ok, data} | {:error, reason}
  def recv(%{transport: transport, socket: socket}, size, timeout \\ @default_timeout) do
    transport.recv(socket, size, timeout)
  end

  defp setopts_mod(:ssl), do: :ssl
  defp setopts_mod(:gen_tcp), do: :inet

  defp tcp_opts(%{use_tls: true}) do

    # Disable TLS verification in dev/test so that self-signed certs will work
    verify_opts =
      case Faktory.Utils.env do
        :prod -> [verify: :verify_peer]
        _     -> [verify: :verify_none]
      end

    tcp_opts(nil) ++
    verify_opts ++
    [versions: [:'tlsv1.2'], depth: 99, cacerts: :certifi.cacerts()]
  end

  defp tcp_opts(_) do
    [:binary, active: false]
  end

end
