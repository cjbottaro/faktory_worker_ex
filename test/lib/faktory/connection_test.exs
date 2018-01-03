defmodule Faktory.ConnectionTest do
  use ExUnit.Case, async: true

  alias Faktory.Tcp.Mock
  alias Faktory.Connection

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
      test_pid: self(),
      host: nil,
      port: nil,
      use_tls: false,
      wid: "123abc",
      password: nil
    })

    assert_receive :handshake_done

    output = Mock.get_send_buf(mock)
    unix_pid = System.get_pid |> String.to_integer
    assert output == ~s(HELLO {"wid":"123abc","v":2,"pid":#{unix_pid},"labels":["elixir"],"hostname":"kaby"}\r\n)
  end

end
