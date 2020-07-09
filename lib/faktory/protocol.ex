defmodule Faktory.Protocol do
  @moduledoc false

  # So we can use our send/2 defined below.
  import Kernel, except: [send: 2]

  def push(conn, job) when is_list(job), do: push(conn, Map.new(job))

  def push(conn, job) do
    payload = Jason.encode!(job)

    with :ok <- send(conn, "PUSH #{payload}"),
         {:ok, "+OK"} <- recv(conn, :line) do
      {:ok, job["jid"]}
    end
  end

  def fetch(conn, queues) when is_list(queues) do
    fetch(conn, Enum.join(queues, " "))
  end

  def fetch(conn, queues) when is_binary(queues) do
    with :ok <- send(conn, "FETCH #{queues}"),
         {:ok, <<"$", size::binary>>} <- recv(conn, :line),
         {:size, size} when size != "-1" <- {:size, size},
         {:ok, json} <- recv(conn, String.to_integer(size)),
         {:ok, ""} <- recv(conn, :line) do
      {:ok, Jason.decode!(json)}
    else
      {:size, "-1"} -> {:ok, nil}
      error -> error
    end
  end

  def ack(conn, jid) when is_binary(jid) do
    payload = %{"jid" => jid} |> Jason.encode!()

    with :ok <- send(conn, "ACK #{payload}"),
         {:ok, "+OK"} <- recv(conn, :line) do
      {:ok, jid}
    end
  end

  def fail(conn, jid, errtype, message, backtrace) do
    payload =
      %{
        jid: jid,
        errtype: errtype,
        message: message,
        backtrace: backtrace
      }
      |> Jason.encode!()

    with :ok <- send(conn, "FAIL #{payload}"),
         {:ok, "+OK"} <- recv(conn, :line) do
      {:ok, jid}
    end
  end

  def info(conn) do
    with :ok <- send(conn, "INFO"),
         {:ok, <<"$", size::binary>>} <- recv(conn, :line),
         size = String.to_integer(size),
         {:ok, json} <- recv(conn, size),
         {:ok, ""} <- recv(conn, :line) do
      Jason.decode(json)
    end
  end

  def beat(conn, wid) do
    payload = %{wid: wid} |> Jason.encode!()

    with :ok <- send(conn, "BEAT #{payload}"),
         {:ok, "+OK"} <- recv(conn, :line) do
      :ok
    else
      {:ok, json} -> {:ok, Jason.decode!(json)}
      error -> error
    end
  end

  def flush(conn) do
    with :ok <- send(conn, "FLUSH"),
         {:ok, "+OK"} <- recv(conn, :line) do
      :ok
    end
  end

  defp send(conn, data) do
    Faktory.Connection.send(conn, data)
  end

  defp recv(conn, :line) do
    case Faktory.Connection.recv(conn, :line) do
      {:ok, <<"-ERR ", reason::binary>>} -> {:error, reason}
      {:ok, <<"-SHUTDOWN ", reason::binary>>} -> {:error, reason}
      {:ok, line} -> {:ok, line}
      error -> error
    end
  end

  defp recv(conn, size) do
    Faktory.Connection.recv(conn, size)
  end
end
