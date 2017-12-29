defmodule Faktory.ConnectionTest do
  use ExUnit.Case, async: false # Can't use async cuz Faktory.Tcp.Mock uses
                                # a globally named GenServer.

  alias Faktory.Tcp.Mock
  alias Faktory.Connection

  setup do
    mock = case Process.whereis(Mock) do
      nil ->
        Mock.start_link |> elem(1)
      pid ->
        GenServer.stop(pid)
        Mock.start_link |> elem(1)
    end
    {:ok, mock: mock}
  end

  test "handshake!", %{mock: mock} do
    buf = "+HI"
      <> Poison.encode!(%{v: 2})
      <> "\r\n"
      <> "+OK\r\n"
    Mock.put_recv_buf(mock, buf)

    {:ok, _pid} = Connection.start_link(%{
      tcp: Mock,
      host: nil,
      port: nil,
      use_tls: false,
      wid: "123abc",
      password: nil
    })
    :timer.sleep(10) # Ugh, I hate this.

    output = Mock.get_send_buf(mock)
    unix_pid = System.get_pid |> String.to_integer
    assert output == ~s(HELLO {"wid":"123abc","v":2,"pid":#{unix_pid},"labels":["elixir"],"hostname":"kaby"}\r\n)
  end

end
