defmodule Faktory.Reporter do
  @moduledoc false

  defstruct [:config, :conn]

  alias Faktory.{Utils, Logger}

  def start_link(config) do
    Task.start_link(__MODULE__, :run, [config])
  end

  def run(config) do
    {:ok, conn} = Faktory.Connection.start_link(config)
    report_queue = Faktory.Registry.name(config.module, :report_queue)

    Stream.repeatedly(fn -> BlockingQueue.pop(report_queue) end)
    |> Enum.each(&report(conn, &1))
  end

  defp report(conn, result) do
    case result do
      {:ack, jid} -> ack(conn, jid)
      {:fail, jid, info} -> fail(conn, jid, info)
    end
  end

  defp ack(conn, jid, errors \\ 0) do
    case Faktory.Protocol.ack(conn, jid) do
      {:ok, jid} -> log_success(:ack, jid)
      {:error, reason} ->
        log_and_sleep(:ack, reason, errors)
        ack(conn, jid, errors + 1) # Retry
    end
  end

  defp fail(conn, jid, info, errors \\ 0) do
    errtype = info[:errtype]
    message = info[:message]
    trace   = info[:trace]

    case Faktory.Protocol.fail(conn, jid, errtype, message, trace) do
      {:ok, jid} -> log_success(:fail, jid)
      {:error, reason} ->
        log_and_sleep(:fail, reason, errors)
        fail(conn, jid, info, errors + 1) # Retry
    end
  end

  defp log_success(op, jid) do
    Logger.debug("#{op} success: #{jid}")
  end

  defp log_and_sleep(op, reason, _errors) do
    reason = Utils.stringify(reason)
    retry_time = 1000 # TODO exponential backoff based of errors
    Logger.warn("#{op} failure: #{reason} -- retrying in #{retry_time/1000}s")
    Process.sleep(retry_time)
  end

end
