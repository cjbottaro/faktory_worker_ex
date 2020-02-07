defmodule Faktory.ConnectionTest do
  use ExUnit.Case, async: true

  alias Faktory.{Connection, Utils}
  import Mox

  setup :verify_on_exit!

  test "handshake" do
    hi = "+HI"
      <> Jason.encode!(%{v: 2})
      <> "\r\n"
    hello = "HELLO "
      <> Jason.encode!(%{
        wid: "123abc",
        v: 2,
        pid: Utils.unix_pid,
        labels: ["elixir"],
        hostname: Utils.hostname})
      <> "\r\n"

    Faktory.SocketMock
    |> expect(:connect, fn _ -> {:ok, nil} end)
    |> expect(:recv, fn _, :line, _ -> {:ok, hi} end)
    |> expect(:send, fn _, data -> assert data == hello; :ok end)
    |> expect(:recv, fn _, :line, _ -> {:ok, "+OK"} end)

    parent = self()

    {:ok, _pid} = Connection.start_link(%{
      socket_impl: Faktory.SocketMock,
      on_init: (fn -> allow(Faktory.SocketMock, parent, self()) end),
      on_connect: (fn -> send(parent, :connected) end),
      host: nil,
      port: nil,
      use_tls: false,
      wid: "123abc",
      password: nil
    })

    receive do
      :connected -> nil
    end

  end

end
