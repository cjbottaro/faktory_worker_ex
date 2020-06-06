defmodule Faktory.Tracker do
  @moduledoc false

  defmodule Job do
    @moduledoc false
    defstruct [:payload, :fetch_time, :start_time, :worker_pid]
  end

  use GenServer

  def child_spec(config) do
    %{
      id: {config.module, __MODULE__},
      start: {__MODULE__, :start_link, [config]},
      shutdown: config.shutdown_grace_period
    }
  end

  def name(config) do
    Faktory.Registry.name({config.module, __MODULE__, :tracker})
  end

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: name(config))
  end

  def init(config) do
    Process.flag(:trap_exit, true)

    Faktory.Logger.debug "Tracker stage #{inspect self()} starting up"

    {:ok, conn} = Faktory.Connection.start_link(config)

    state = %{
      config: config,
      conn: conn,
      jobs: %{},
      start_status: "S 🚀",
      ack_status: "A 🥂",
      fail_status: "F 💥"
    }

    {:ok, state}
  end

  # Note that that timeout is :infinity. All communication with the Faktory
  # server retries, so there is no point in timing out and trying to continue.

  def fetch(server, payload) do
    GenServer.call(server, {:fetch, payload}, :infinity)
  end

  def start(server, jid) do
    GenServer.call(server, {:start, jid}, :infinity)
  end

  def ack(server, jid) do
    GenServer.call(server, {:ack, jid}, :infinity)
  end

  def fail(server, jid, reason) do
    GenServer.call(server, {:fail, jid, reason}, :infinity)
  end

  def handle_call({:fetch, payload}, _from, state) do
    job = %Job{payload: payload, fetch_time: System.monotonic_time(:millisecond)}
    state = %{state | jobs: Map.put(state.jobs, payload["jid"], job)}
    {:reply, :ok, state}
  end

  def handle_call({:start, jid}, {pid, _ref}, state) do
    job = %{state.jobs[jid] | worker_pid: pid, start_time: System.monotonic_time(:millisecond)}

    status = state.start_status
    worker_pid = job.worker_pid
    jobtype = job.payload["jobtype"]
    args = job.payload["args"]

    Faktory.Logger.info "#{status} #{inspect worker_pid} jid-#{jid} (#{jobtype}) #{inspect args}"

    {:reply, :ok, put_in(state.jobs[jid], job)}
  end

  def handle_call({:ack, jid}, _from, state) do
    {job, jobs} = Map.pop!(state.jobs, jid)
    conn        = state.conn
    status      = state.ack_status
    worker_pid  = job.worker_pid
    jobtype     = job.payload["jobtype"]
    time        = Faktory.Utils.elapsed(job.start_time)

    retry_until_ok("ACK", fn -> Faktory.Protocol.ack(conn, jid) end)

    Faktory.Logger.info "#{status} #{inspect worker_pid} jid-#{jid} (#{jobtype}) #{time}s"

    {:reply, :ok, %{state | jobs: jobs}}
  end

  def handle_call({:fail, jid, reason}, _from, state) do
    {job, jobs} = Map.pop!(state.jobs, jid)
    conn        = state.conn
    status      = state.fail_status
    worker_pid  = job.worker_pid || self()
    jobtype     = job.payload["jobtype"]
    time        = job.start_time && Faktory.Utils.elapsed(job.start_time)

    %{errtype: errtype, message: message, trace: trace} = Faktory.Error.from_reason(reason)
    retry_until_ok("FAIL", fn -> Faktory.Protocol.fail(conn, jid, errtype, message, trace) end)

    if time do
      Faktory.Logger.info "#{status} #{inspect worker_pid} jid-#{jid} (#{jobtype}) #{time}s"
    else
      # Job was fetched, but not started.
      Faktory.Logger.info "#{status} #{inspect worker_pid} jid-#{jid} (#{jobtype})"
    end

    {:reply, :ok, %{state | jobs: jobs}}
  end

  defp retry_until_ok(cmd, f) do
    Stream.repeatedly(f)
    |> Enum.reduce_while(0, fn

      # Everything went smoothly.
      {:ok, "OK"}, _count ->
        {:halt, :ok}

      # Server error. Log and move on.
      {:ok, {:error, reason}}, _count ->
        Faktory.Logger.warn("Server error on #{cmd}: #{reason} -- moving on")
        {:halt, :ok}

      # Network error. Log, sleep, and retry.
      {:error, reason}, count ->
        time = Faktory.Utils.exp_backoff(count)
        Faktory.Logger.warn("Network error on #{cmd}: #{reason} -- retrying in #{time/1000}s")
        Process.sleep(time)
        {:cont, count+1}
    end)
  end

  def terminate(reason, state) do
    # Check that the fetcher is shutdown.
    {_, _, name} = Faktory.Stage.Fetcher.name(state.config)
    case Registry.whereis_name(name) do
      :undefined -> nil # Ok, all good.
      pid -> Faktory.Logger.warn "Fetcher stage #{inspect pid} still running"
    end

    # Check that the workers are shutdown.
    Enum.each (1..state.config.concurrency), fn i ->
      {_, _, name} = Faktory.Stage.Worker.name(state.config, i)
      case Registry.whereis_name(name) do
        :undefined -> nil # Ok, all good.
        pid -> Faktory.Logger.warn "Worker stage #{inspect pid} still running"
      end
    end

    # Fail any remaining in-flight jobs.
    Enum.each state.jobs, fn {jid, _job} ->
      {:reply, :ok, _state} = handle_call({:fail, jid, reason}, self(), state)
    end
  end

end
