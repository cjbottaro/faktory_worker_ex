defmodule Faktory.Reporter do
  @moduledoc false

  defstruct [:config, :conn]

  use GenStage

  alias Faktory.{Utils, Logger}
  import Utils, only: [if_test: 1]

  def start_link(config) do
    name = Faktory.Registry.name({config.module, __MODULE__})
    GenStage.start_link(__MODULE__, config, name: name)
  end

  def init(config) do
    {:ok, conn} = Faktory.Connection.start_link(config)
    state = %__MODULE__{config: config, conn: conn}
    {:consumer, state, subscribe_to: subscribe_to(config)}
  end

  def handle_events([job_task], _from, state) do
    report(state.conn, job_task)
    {:noreply, [], state}
  end

  defp subscribe_to(config) do
    (1..config.concurrency)
    |> Enum.map(fn index ->
      producer_name = Faktory.Registry.name({config.module, Faktory.JobWorker, index})
      {producer_name, max_demand: 1, min_demand: 0}
    end)
  end

  defp report(conn, job_task) do
    case job_task do
      %{error: nil} -> ack(conn, job_task)
      %{error: _error} -> fail(conn, job_task)
    end
  end

  defp ack(conn, job_task, error_count \\ 0) do
    jid = job_task.job["jid"]

    case Faktory.Protocol.ack(conn, jid) do
      {:ok, _jid} ->
        if_test do: send TestJidPidMap.get(jid), %{jid: jid, error: nil}
        log("SUCCESS 🥂", job_task)
      {:error, reason} ->
        warn_and_sleep(:ack, reason, error_count)
        ack(conn, job_task, error_count + 1) # Retry
    end
  end

  defp fail(conn, job_task, error_count \\ 0) do
    jid = job_task.job["jid"]
    errtype = job_task.error.errtype
    message = job_task.error.message
    trace   = job_task.error.trace

    case Faktory.Protocol.fail(conn, jid, errtype, message, trace) do
      {:ok, _jid} ->
        if_test do: send TestJidPidMap.get(jid), %{jid: jid, error: job_task.error}
        log("FAILURE 💥", job_task)
      {:error, reason} ->
        warn_and_sleep(:fail, reason, error_count)
        fail(conn, job_task, error_count + 1) # Retry
    end
  end

  defp log(status, job_task) do
    jid = job_task.job["jid"]
    jobtype = job_task.job["jobtype"]
    worker_pid = job_task.worker_pid
    time = elapsed(job_task.start_time)
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
