defmodule Faktory.Reporter do
  @moduledoc false

  defstruct [:config, :conn]

  use GenStage

  alias Faktory.{Utils, Logger}
  import Utils, only: [if_test: 1]

  def start_link(config, index) do
    name = Faktory.Registry.name({config.module, __MODULE__, index})
    GenStage.start_link(__MODULE__, config, name: name)
  end

  def init(config) do
    {:ok, conn} = Faktory.Connection.start_link(config)
    state = %__MODULE__{config: config, conn: conn}
    {:consumer, state, subscribe_to: subscribe_to(config)}
  end

  def handle_events([report], _from, state) do
    report(state.conn, report)
    {:noreply, [], state}
  end

  defp subscribe_to(config) do
    (1..config.concurrency)
    |> Enum.map(fn index ->
      producer_name = Faktory.Registry.name({config.module, Faktory.JobWorker, index})
      {producer_name, max_demand: 1, min_demand: 0}
    end)
  end

  defp report(conn, report) do
    case report do
      %{error: nil} -> ack(conn, report)
      %{error: _error} -> fail(conn, report)
    end
  end

  defp ack(conn, report, error_count \\ 0) do
    jid = report.job["jid"]

    case Faktory.Protocol.ack(conn, jid) do
      {:ok, _jid} ->
        if_test do: send TestJidPidMap.get(jid), %{jid: jid, error: nil}
        log("SUCCESS 🥂", report)
      {:error, reason} ->
        warn_and_sleep(:ack, reason, error_count)
        ack(conn, report, error_count + 1) # Retry
    end
  end

  defp fail(conn, report, error_count \\ 0) do
    jid = report.job["jid"]
    errtype = report.error.errtype
    message = report.error.message
    trace   = report.error.trace

    case Faktory.Protocol.fail(conn, jid, errtype, message, trace) do
      {:ok, _jid} ->
        if_test do: send TestJidPidMap.get(jid), %{jid: jid, error: report.error}
        log("FAILURE 💥", report)
      {:error, reason} ->
        warn_and_sleep(:fail, reason, error_count)
        fail(conn, report, error_count + 1) # Retry
    end
  end

  defp log(status, report) do
    jid = report.job["jid"]
    jobtype = report.job["jobtype"]
    worker_pid = report.worker_pid
    time = elapsed(report.start_time)
    Faktory.Logger.info "#{status} #{inspect worker_pid} jid-#{jid} (#{jobtype}) #{time}s"
  end

  defp warn_and_sleep(op, reason, errors) do
    reason = Utils.stringify(reason)
    sleep_time = Utils.exp_backoff(errors)
    Logger.warn("#{op} failure: #{reason} -- retrying in #{sleep_time/1000}s")
    Process.sleep(sleep_time)
  end

  defp elapsed(start_time) do
    (System.monotonic_time(:millisecond) - start_time) / 1000
  end

end
