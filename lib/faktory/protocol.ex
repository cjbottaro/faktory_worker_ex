# Speak RESP with the Faktory server.
# Return value should be one of three things:
#   {:ok, result}           # All good.
#   {:error, reason}        # Network error, ok to retry.
#   {:ok, {:error, reason}} # Server error (aka RESP error), probably can't retry.
defmodule Faktory.Protocol do
  @moduledoc false

  @type success       :: {:ok, binary}
  @type network_error :: {:error, reason :: binary}
  @type server_error  :: {:ok, {:error, reason :: binary}}

  @type conn :: Faktory.Connection.t
  @type job :: Map.t | Keyword.t

  @type jid :: binary

  alias Faktory.{Connection, Resp}

  def handshake(conn, hello) do
    with \
      {:ok, <<"HI", json::binary>>} <- Resp.recv(conn),
      {:ok, server} <- Jason.decode(json),
      {:ok, hello} <- build_hello(hello, server),
      :ok <- Connection.send(conn, "HELLO #{hello}"),
      {:ok, "OK"} <- Resp.recv(conn)
    do
      {:ok, server}
    end
  end

  defp build_hello(hello, server) do
    case server do
      %{"s" => salt, "i" => iterations} ->
        pwdhash = (hello.password || "") |> Utils.hash_password(salt, iterations)
        Map.put(hello, :pwdhash, pwdhash)

      _ -> hello
    end
    |> Map.delete(:password)
    |> Jason.encode(hello)
  end

  @spec push(conn, job) :: success | network_error | server_error

  def push(conn, job) when is_list(job), do: push(conn, Map.new(job))

  def push(conn, job) do
    payload = Jason.encode!(job)

    with :ok <- Connection.send(conn, "PUSH #{payload}") do
      Resp.recv(conn)
    end
  end

  def fetch(conn, queues) when is_list(queues) do
    fetch(conn, Enum.join(queues, " "))
  end

  def fetch(conn, queues) when is_binary(queues) do
    with \
      :ok <- Connection.send(conn, "FETCH #{queues}"),
      {:ok, <<json::binary>>} <- Resp.recv(conn)
    do
      {:ok, Jason.decode!(json)}
    end
  end

  def ack(conn, jid) when is_binary(jid) do
    payload = %{"jid" => jid} |> Jason.encode!

    with :ok <- Connection.send(conn, "ACK #{payload}") do
      Resp.recv(conn)
    end
  end

  def fail(conn, jid, errtype, message, backtrace) do
    payload = %{
      jid: jid,
      errtype: errtype,
      message: message,
      backtrace: backtrace
    } |> Jason.encode!

    with :ok <- Connection.send(conn, "FAIL #{payload}") do
      Resp.recv(conn)
    end
  end

  def info(conn) do
    with \
      :ok <- Connection.send(conn, "INFO"),
      {:ok, <<json::binary>>} <- Resp.recv(conn)
    do
      {:ok, Jason.decode!(json)}
    end
  end

  def beat(conn, wid) do
    payload = %{wid: wid} |> Jason.encode!

    with :ok <- Connection.send(conn, "BEAT #{payload}") do
      Resp.recv(conn)
    end
  end

  def flush(conn) do
    with :ok <- Connection.send(conn, "FLUSH") do
      Resp.recv(conn)
    end
  end

end
