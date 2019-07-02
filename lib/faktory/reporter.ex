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
      producer_name = Faktory.Registry.name({config.module, Faktory.Runner, index})
      {producer_name, max_demand: 1, min_demand: 0}
    end)
  end

  defp report(conn, report) do
    case report do
      %{error: nil} -> ack(conn, report)
      %{error: _error} -> fail(conn, report)
    end
  end

  defp ack(conn, report) do
    jid = report.job["jid"]

    Stream.repeatedly(fn -> Faktory.Protocol.ack(conn, jid) end)
    |> Enum.reduce_while(0, fn
      # Everything went smoothly.
      {:ok, "OK"}, _count ->
        log("SUCCESS 🥂", report)
        {:halt, :ok}

      # Server error. Log and move on.
      {:ok, {:error, reason}}, _count ->
        Logger.warn("Server error on ack: #{reason}")
        {:halt, :ok}

      # Network error. Log, sleep, and retry.
      {:error, reason}, count ->
        warn_and_sleep("ack", reason, count)
        {:cont, count+1}
    end)
  end

  defp fail(conn, report) do
    jid = report.job["jid"]
    errtype = report.error.errtype
    message = report.error.message
    trace   = report.error.trace

    Stream.repeatedly(fn -> Faktory.Protocol.fail(conn, jid, errtype, message, trace) end)
    |> Enum.reduce_while(0, fn
      # Everything went smoothly.
      {:ok, "OK"}, _count ->
        log("FAILURE 💥", report)
        {:halt, :ok}

      # Server error. Log and move on.
      {:ok, {:error, reason}}, _count ->
        Logger.warn("Server error on ack: #{reason}")
        {:halt, :ok}

      # Network error. Log, sleep, and retry.
      {:error, reason}, count ->
        warn_and_sleep("fail", reason, count)
        {:cont, count+1}
    end)
  end

  defp warn_and_sleep(command, reason, count) do
    time = Utils.exp_backoff(count)
    Logger.warn("Network error on #{command}: #{reason} -- retrying in #{time/1000}s")
    Process.sleep(time)
  end

  defp log(status, report) do
    jid = report.job["jid"]
    jobtype = report.job["jobtype"]
    worker_pid = report.worker_pid
    time = Utils.elapsed(report.start_time)
    Logger.info "#{status} #{inspect worker_pid} jid-#{jid} (#{jobtype}) #{time}s"

    if_test do
      send TestJidPidMap.get(jid), %{jid: jid, error: report.error}
    end
  end

end
