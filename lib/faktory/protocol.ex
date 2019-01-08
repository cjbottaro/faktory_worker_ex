defmodule Faktory.Protocol do
  @moduledoc false

  alias Faktory.Connection

  # A Faktory.Connection uses the Connection module which means it
  # will automatically try to reconnect on disconnections or errors.
  # That's why we use retryable here; a connection can heal itself
  # as opposed to letting a supervisor restart it.
  import Retryable
  @retry_options [
    on: :error,
    tries: 60,
    sleep: 1.0
  ]

  def push(conn, job) when is_list(job), do: push(conn, Map.new(job))

  def push(conn, job) do
    payload = Poison.encode!(job)

    retryable @retry_options, fn ->
      with :ok <- Connection.send(conn, "PUSH #{payload}"),
        {:ok, "OK"} <- Connection.recv(conn, :line)
      do
        job["jid"]
      end
    end
  end

  def fetch(conn, queues) when is_list(queues) do
    fetch(conn, Enum.join(queues, " "))
  end

  def fetch(conn, queues) when is_binary(queues) do
    retryable @retry_options, fn ->
      with :ok <- Connection.send(conn, "FETCH #{queues}"),
        {:ok, <<"$", size::binary>>} <- Connection.recv(conn, :line),
        {:size, size} when size != "-1" <- {:size, size},
        {:ok, json} <- Connection.recv(conn, String.to_integer(size)),
        {:ok, ""} <- Connection.recv(conn, :line)
      do
        Poison.decode!(json)
      else
        {:size, "-1"} -> nil
        error -> error
      end
    end
  end

  def ack(conn, jid) when is_binary(jid) do
    payload = %{"jid" => jid} |> Poison.encode!

    retryable @retry_options, fn ->
      with :ok <- Connection.send(conn, "ACK #{payload}"),
        {:ok, "OK"} <- Connection.recv(conn, :line)
      do
        {:ok, jid}
      end
    end
  end

  def fail(conn, jid, errtype, message, backtrace) do
    payload = %{
      jid: jid,
      errtype: errtype,
      message: message,
      backtrace: backtrace
    } |> Poison.encode!

    retryable @retry_options, fn ->
      with :ok <- Connection.send(conn, "FAIL #{payload}"),
        {:ok, "OK"} <- Connection.recv(conn, :line)
      do
        {:ok, jid}
      end
    end
  end

  def info(conn) do
    retryable @retry_options, fn ->
      with :ok <- Connection.send(conn, "INFO"),
        {:ok, <<"$", size::binary>>} <- Connection.recv(conn, :line),
        size = String.to_integer(size),
        {:ok, json} <- Connection.recv(conn, size),
        {:ok, ""} <- Connection.recv(conn, :line)
      do
        Poison.decode(json)
      end
    end
  end

  def beat(conn, wid) do
    payload = %{wid: wid} |> Poison.encode!

    retryable @retry_options, fn ->
      with :ok <- Connection.send(conn, "BEAT #{payload}"),
        {:ok, "OK"} <- Connection.recv(conn, :line)
      do
        :ok
      else
        {:ok, json} -> {:ok, Poison.decode!(json)}
        error -> error
      end
    end
  end

  def flush(conn) do
    retryable @retry_options, fn ->
      with :ok <- Connection.send(conn, "FLUSH"),
        {:ok, "OK"} <- Connection.recv(conn, :line)
      do
        :ok
      end
    end
  end

end
