defmodule Faktory.ConnectionTest do
  use ExUnit.Case, async: true

  alias Faktory.{Connection, Utils}
  import Mox

  setup :verify_on_exit!

  @tag :pending
  test "handshake!" do
    hi = "+HI"
      <> Poison.encode!(%{v: 2})
      <> "\r\n"
    hello = "HELLO "
      <> Poison.encode!(%{
        wid: "123abc",
        v: 2,
        pid: Utils.unix_pid,
        labels: ["elixir"],
        hostname: Utils.hostname})
      <> "\r\n"

    Faktory.Tcp.Mock
    |> expect(:connect, fn _ -> {:ok, nil} end)
    |> expect(:setup_size, fn _, :line -> 0 end)
    |> expect(:recv, fn _, 0 -> {:ok, hi} end)
    |> expect(:send, fn _, data -> assert data == hello; :ok end)
    |> expect(:recv, fn _, 0 -> {:ok, "+OK\r\n"} end)

    parent = self()

    {:ok, _pid} = Connection.start_link(%{
      tcp: Faktory.Tcp.Mock,
      on_init: (fn -> allow(Faktory.Tcp.Mock, parent, self()) end),
      host: nil,
      port: nil,
      use_tls: false,
      wid: "123abc",
      password: nil
    })
  end

end
