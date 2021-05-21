defmodule Faktory.Socket do
  @moduledoc false

  def connect(host, port, opts \\ [])

  def connect(host, port, opts) when is_binary(host) do
    connect(String.to_charlist(host), port, opts)
  end

  def connect(host, port, opts) do
    if {:tls, true} in opts do
      opts = List.delete(opts, {:tls, true})
      :ssl.connect(host, port, opts)
    else
      opts = List.delete(opts, {:tls, false})
      :gen_tcp.connect(host, port, opts)
    end
  end

  def close(socket) when is_port(socket) do
    :gen_tcp.close(socket)
  end

  def close(socket) when is_tuple(socket) do
    :ssl.close(socket)
  end

  def active(socket, how) when is_port(socket) and how in [:once, false] do
    :inet.setopts(socket, active: how)
  end

  def active(socket, how) when is_tuple(socket) and how in [:once, false] do
    :ssl.setopts(socket, active: how)
  end

  def recv(socket, :line) when is_port(socket) do
    {usec, result} = :timer.tc(fn -> :gen_tcp.recv(socket, 0) end)

    :telemetry.execute(
      [:faktory, :socket, :recv],
      %{usec: usec},
      %{result: result}
    )

    result
  end

  def recv(socket, :line) when is_tuple(socket) do
    {usec, result} = :timer.tc(fn -> :ssl.recv(socket, 0) end)

    :telemetry.execute(
      [:faktory, :socket, :recv],
      %{usec: usec},
      %{result: result}
    )

    result
  end

  def recv(socket, n) when is_port(socket) and is_integer(n) do
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

  def recv(socket, n) when is_tuple(socket) and is_integer(n) do
    {usec, result} = :timer.tc(fn ->
      :ok = :ssl.setopts(socket, packet: :raw)
      result = :ssl.recv(socket, n)
      :ok = :ssl.setopts(socket, packet: :line)
      result
    end)

    :telemetry.execute(
      [:faktory, :socket, :recv],
      %{usec: usec},
      %{result: result}
    )

    result
  end

  def send(socket, data) when is_port(socket) do
    {usec, result} = :timer.tc(fn -> :gen_tcp.send(socket, data) end)

    :telemetry.execute(
      [:faktory, :socket, :send],
      %{usec: usec},
      %{result: result, data: data}
    )

    result
  end

  def send(socket, data) when is_tuple(socket) do
    {usec, result} = :timer.tc(fn -> :ssl.send(socket, data) end)

    :telemetry.execute(
      [:faktory, :socket, :send],
      %{usec: usec},
      %{result: result, data: data}
    )

    result
  end

end
