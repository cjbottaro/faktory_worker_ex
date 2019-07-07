defmodule Faktory.Stage.Reporter do
  @moduledoc false

  defstruct [:config, :conn]

  use GenStage

  alias Faktory.{Utils, Logger}
  import Utils, only: [if_test: 1]

  def child_spec({config, index}) do
    %{
      id: {config.module, __MODULE__, index},
      start: {__MODULE__, :start_link, [config, index]}
    }
  end

  def name(config, index) do
    Faktory.Registry.name({config.module, __MODULE__, index})
  end

  def start_link(config, index) do
    GenStage.start_link(__MODULE__, config, name: name(config, index))
  end

  def init(config) do
    Faktory.Logger.debug "Reporter stage #{inspect self()} starting up"
    {:ok, conn} = Faktory.Connection.start_link(config)
    state = %__MODULE__{config: config, conn: conn}
    {:consumer, state, subscribe_to: subscribe_to(config)}
  end

  def handle_events([report], _from, state) do
    conn = state.conn
    jid = report.job["jid"]

    f = case report do
      %{error: nil} ->
        fn -> Faktory.Protocol.ack(conn, jid) end
      %{error: error} ->
        fn -> Faktory.Protocol.fail(conn, jid, error.errtype, error.message, error.trace) end
    end

    cmd = if report[:error] do
      "fail"
    else
      "ack"
    end

    Stream.repeatedly(f)
    |> Enum.reduce_while(0, fn

      # Everything went smoothly.
      {:ok, "OK"}, _count ->
        log(cmd, report)
        {:halt, :ok}

      # Server error. Log and move on.
      {:ok, {:error, reason}}, _count ->
        Logger.warn("Server error on #{cmd}: #{reason} -- moving on")
        {:halt, :ok}

      # Network error. Log, sleep, and retry.
      {:error, reason}, count ->
        time = Faktory.Utils.exp_backoff(count)
        Logger.warn("Network error on #{cmd}: #{reason} -- retrying in #{time/1000}s")
        Process.sleep(time)
        {:cont, count+1}
    end)

    {:noreply, [], state}
  end

  defp log(cmd, report) do
    status = case cmd do
      "ack"  -> "S 🥂"
      "fail" -> "F 💥"
    end

    jid = report.job["jid"]
    jobtype = report.job["jobtype"]
    worker_pid = report.worker_pid
    time = Utils.elapsed(report.start_time)
    Logger.info "#{status} #{inspect worker_pid} jid-#{jid} (#{jobtype}) #{time}s"

    if_test do
      send TestJidPidMap.get(jid), %{jid: jid, error: report.error}
    end
  end

  defp subscribe_to(config) do
    (1..config.concurrency)
    |> Enum.map(fn index ->
      producer_name = Faktory.Stage.Worker.name(config, index)
      {producer_name, max_demand: 1, min_demand: 0}
    end)
  end

end
