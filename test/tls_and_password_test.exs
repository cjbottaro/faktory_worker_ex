defmodule TlsAndPasswordTest do
  use ExUnit.Case, async: false

  test "can connect to password protected server" do
    {:ok, conn} = Faktory.Connection.start_link(port: 7423, tls: true, password: "123abc")
    {:ok, _info} = Faktory.Connection.info(conn)
  end

  test "rejects invalid passwords" do
    {:error, "Invalid password"} = Faktory.Connection.start_link(port: 7423, tls: true, password: "abc123")
  end
end
