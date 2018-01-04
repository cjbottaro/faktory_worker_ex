defmodule Faktory.ConnectionTest do
  use ExUnit.Case, async: true

  alias Faktory.Tcp.Mock
  alias Faktory.{Connection, Utils}

  test "handshake!" do
    buf = "+HI"
      <> Poison.encode!(%{v: 2})
      <> "\r\n"
      <> "+OK\r\n"
    {:ok, mock} = Mock.start_link
    Mock.put_recv_buf(mock, buf)

    {:ok, _pid} = Connection.start_link(%{
      tcp: Mock,
      mock_pid: mock,
      host: nil,
      port: nil,
      use_tls: false,
      wid: "123abc",
      password: nil
    })

    output = Mock.get_send_buf(mock)
    assert output == ~s(HELLO {"wid":"123abc","v":2,"pid":#{Utils.unix_pid},"labels":["elixir"],"hostname":"#{Utils.hostname}"}\r\n)
  end

end
