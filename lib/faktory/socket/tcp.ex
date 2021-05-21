defmodule Faktory.Socket.Tcp do
  @moduledoc false
  defstruct [:socket]

  def connect(host, port, opts \\ []) do
    host = String.to_charlist(host)
    case :gen_tcp.connect(host, port, opts) do
      {:ok, socket} -> {:ok, %__MODULE__{socket: socket}}
      error -> error
    end
  end

end

defimpl Faktory.Socket, for: Faktory.Socket.Tcp do

  def close(%{socket: socket}) do
    :gen_tcp.close(socket)
  end

  def active(%{socket: socket}, how) when how in [:once, false] do
    :inet.setopts(socket, active: how)
  end

  def recv(%{socket: socket}, :line) do
    {usec, result} = :timer.tc(fn -> :gen_tcp.recv(socket, 0) end)

    :telemetry.execute(
      [:faktory, :socket, :recv],
      %{usec: usec},
      %{result: result}
    )

    result
  end

  def recv(%{socket: socket}, n) when is_integer(n) do
    {usec, result} = :timer.tc(fn ->
      :ok = :inet.setopts(socket, packet: :raw)
      result = :gen_tcp.recv(socket, n)
      :ok = :inet.setopts(socket, packet: :line)
      result
    end)

    :telemetry.execute(
      [:faktory, :socket, :recv],
      %{usec: usec},
      %{result: result}
    )

    result
  end

  def send(%{socket: socket}, data) do
    {usec, result} = :timer.tc(fn -> :gen_tcp.send(socket, data) end)

    :telemetry.execute(
      [:faktory, :socket, :send],
      %{usec: usec},
      %{result: result, data: data}
    )

    result
  end

end
