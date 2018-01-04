defmodule Faktory.Tcp.Mock do
  defstruct [line_mode: false, recv_buf: "", send_buf: ""]

  def connect(options), do: {:ok, options.mock_pid}

  # Returns :ok
  def close(_), do: :ok

  # If asking for a line, then go into line mode and get whole line.
  def setup_size(pid, :line) do
    GenServer.call(pid, {:line_mode, true})
    0
  end

  # Asking for a specified number of bytes.
  def setup_size(pid, n) do
    GenServer.call(pid, {:line_mode, false})
    n
  end

  # Returns :ok | {:error, reason}
  def send(pid, data) do
    GenServer.call(pid, {:send, data})
  end

  # Returns {:ok, data} | {:error, reason}
  def recv(pid, size, _timeout \\ nil) do
    GenServer.call(pid, {:recv, size})
  end

  def get_send_buf(pid) do
    GenServer.call(pid, :get_send_buf)
  end

  def put_recv_buf(pid, data) do
    GenServer.call(pid, {:put_recv_buf, data})
  end

  def start_link do
    GenServer.start_link(__MODULE__, nil)
  end

  ####################
  # GenServer stuffs #
  ####################

  def init(_) do
    {:ok, %__MODULE__{}}
  end

  def handle_call({:line_mode, set}, _from, state) do
    {:reply, :ok, %{state | line_mode: set}}
  end

  def handle_call({:send, data}, _from, state) do
    %{send_buf: send_buf} = state
    {:reply, :ok, %{state | send_buf: send_buf <> data}}
  end

  def handle_call({:recv, _size}, _from, %{line_mode: true} = state) do
    %{recv_buf: recv_buf} = state
    [data, recv_buf | []] = String.split(recv_buf, "\r\n", parts: 2)
    {:reply, {:ok, "#{data}\r\n"}, %{state | recv_buf: recv_buf}}
  end

  def handle_call({:recv, size}, _from, %{line_mode: false} = state) do
    %{recv_buf: recv_buf} = state
    <<data::binary-size(size), recv_buf::binary>> = recv_buf
    {:reply, {:ok, "#{data}\r\n"}, %{state | recv_buf: recv_buf}}
  end

  def handle_call(:get_send_buf, _from, state) do
    {:reply, state.send_buf, state}
  end

  def handle_call({:put_recv_buf, data}, _from, state) do
    %{recv_buf: recv_buf} = state
    {:reply, :ok, %{state | recv_buf: recv_buf <> data}}
  end

end
