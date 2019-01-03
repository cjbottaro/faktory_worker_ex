defmodule Faktory.Protocol do
  @moduledoc false

  alias Faktory.Connection
  import Connection, only: [recv: 2]

  # A Faktory.Connection uses the Connection module which means it
  # will automatically try to reconnect on disconnections or errors.
  # That's why we use retryable here; a connection can heal itself
  # as opposed to letting a supervisor restart it.
  import Retryable
  @retry_options [
    on: :error,
    tries: 10,
    sleep: 1.0
  ]

  def push(conn, job) when is_list(job), do: push(conn, Map.new(job))

  def push(conn, job) do
    payload = Poison.encode!(job)

    retryable @retry_options, fn ->
      with :ok <- tx(conn, "PUSH #{payload}"),
        {:ok, "OK"} <- rx(conn)
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
      with :ok <- tx(conn, "FETCH #{queues}"),
        {:ok, job} <- rx(conn)
      do
        job && Poison.decode!(job)
      end
    end
  end

  def ack(conn, jid) when is_binary(jid) do
    payload = %{"jid" => jid} |> Poison.encode!
    retryable @retry_options, fn ->
      with :ok <- tx(conn, "ACK #{payload}"),
        {:ok, "OK"} <- rx(conn)
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
      with :ok <- tx(conn, "FAIL #{payload}"),
        {:ok, "OK"} <- rx(conn)
      do
        {:ok, jid}
      end
    end
  end

  def info(conn) do
    retryable @retry_options, fn ->
      with :ok <- tx(conn, "INFO"),
        {:ok, info} <- rx(conn)
      do
        info && Poison.decode!(info)
      end
    end
  end

  def beat(conn, wid) do
    payload = %{wid: wid} |> Poison.encode!
    retryable @retry_options, fn ->
      with :ok <- tx(conn, "BEAT #{payload}"),
        {:ok, response} <- rx(conn)
      do
        case response do
          "OK" -> :ok
          info -> {:ok, Poison.decode!(info)["signal"]}
        end
      end
    end
  end

  def flush(conn) do
    retryable @retry_options, fn ->
      with :ok <- tx(conn, "FLUSH"),
        {:ok, "OK"} <- rx(conn)
      do
        :ok
      end
    end
  end

  def tx(conn, payload) do
    Connection.send(conn, "#{payload}\r\n")
  end

  def rx(conn) do
    case recv(conn, :line) do
      {:ok, <<"+", rest::binary>>} -> {:ok, rest}
      {:ok, <<"-", error::binary>>} -> {:error, error}
      {:ok, <<"$", size::binary>>} -> rx(conn, size)
      {:error, _} = error -> error
    end
  end

  defp rx(conn, size) when is_binary(size) do
    size = String.to_integer(size)
    rx(conn, size)
  end

  defp rx(_conn, size) when size == -1, do: {:ok, nil}

  defp rx(conn, size) when size == 0 do
    case recv(conn, :line) do
      {:ok, _} -> {:ok, nil}
      {:error, _} = error -> error
    end
  end

  defp rx(conn, size) do
    retval = recv(conn, size)
    case recv(conn, :line) do
      {:ok, _} -> retval
      {:error, _} = error -> error
    end
  end

end
