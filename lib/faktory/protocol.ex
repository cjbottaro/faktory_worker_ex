defmodule Faktory.Protocol do
  @moduledoc false

  alias Faktory.Connection
  import Connection, only: [recv: 2]

  def push(conn, job) when is_list(job), do: push(conn, Map.new(job))

  def push(conn, job) do
    payload = Poison.encode!(job)

    with :ok <- tx(conn, "PUSH #{payload}"),
      {:ok, "OK"} <- rx(conn)
    do
      job["jid"]
    else
      {:error, :closed} -> push(conn, job) # Retries forever and without delay!
      {:error, _message} = error -> error
    end
  end

  def fetch(conn, queues) when is_list(queues) do
    fetch(conn, Enum.join(queues, " "))
  end

  def fetch(conn, queues) when is_binary(queues) do
    with :ok <- tx(conn, "FETCH #{queues}"),
      {:ok, job} <- rx(conn)
    do
      job && Poison.decode!(job)
    else
      {:error, :closed} -> fetch(conn, queues)  # Retries forever and without delay!
      {:error, _message} = error -> error
    end
  end

  def ack(conn, jid) when is_binary(jid) do
    payload = %{"jid" => jid} |> Poison.encode!
    with :ok <- tx(conn, "ACK #{payload}"),
      {:ok, "OK"} <- rx(conn)
    do
      {:ok, jid}
    else
      {:error, :closed} -> ack(conn, jid)  # Retries forever and without delay!
      {:error, _message} = error -> error
    end
  end

  def fail(conn, jid, errtype, message, backtrace) do
    payload = %{
      jid: jid,
      errtype: errtype,
      message: message,
      backtrace: backtrace
    } |> Poison.encode!
    with :ok <- tx(conn, "FAIL #{payload}"),
      {:ok, "OK"} <- rx(conn)
    do
      {:ok, jid}
    else
      {:error, :closed} -> fail(conn, jid, errtype, message, backtrace)  # Retries forever and without delay!
      {:error, _message} = error -> error
    end
  end

  def info(conn) do
    with :ok <- tx(conn, "INFO"),
      {:ok, info} <- rx(conn)
    do
      info && Poison.decode!(info)
    else
      {:error, :closed} -> info(conn)  # Retries forever and without delay!
      {:error, _message} = error -> error
    end
  end

  def beat(conn, wid) do
    payload = %{wid: wid} |> Poison.encode!
    with :ok <- tx(conn, "BEAT #{payload}"),
      {:ok, response} <- rx(conn)
    do
      case response do
        "OK" -> :ok
        info -> {:ok, Poison.decode!(info)["signal"]}
      end
    else
      {:error, :closed} -> beat(conn, wid) # Retries forever and without delay!
      {:error, _message} = error -> error
    end
  end

  def flush(conn) do
    with :ok <- tx(conn, "FLUSH"),
      {:ok, "OK"} <- rx(conn)
    do
      :ok
    else
      {:error, :closed} -> flush(conn) # Retries forever and without delay!
      {:error, _message} = error -> error
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
