defmodule Faktory.Worker do
  @moduledoc false
  use GenServer

  alias Faktory.{Logger, Protocol, Executor}
  import Faktory.Utils, only: [now_in_ms: 0]
  import Faktory.TestHelp, only: [if_test: 1]

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  def init(config) do
    Process.flag(:trap_exit, true)

    # Queue up our mailbox.
    GenServer.cast(self(), :next)

    # Get our state in order.
    state = Map.merge(config, %{
      job: nil,
      worker_pid: nil,
      error: nil,
      start_time: nil,
    })

    # Things are ok!
    {:ok, state}
  end

  # This is the main loop. Fetch a job, execute the job, repeat.
  def handle_cast(:next, state) do
    state = state
      |> fetch
      |> execute
    {:noreply, state}
  end

  # If the worker process errors, it reports its stacktrace to us before ending.
  def handle_call({:error_report, error}, {from, _ref}, %{worker_pid: worker_pid} = state)
  when from == worker_pid do
    Logger.debug("Worker reported an error...\n#{format_error(error)}")
    {:reply, :ok, %{state | error: error}}
  end

  # This gets triggered when the worker process ends. At this point we either
  # have a successully run job or a failure. Either way, we need to restart
  # the main loop.
  def handle_info({:EXIT, pid, :normal}, %{worker_pid: worker_pid} = state)
  when pid == worker_pid do
    Logger.debug("Worker stopped :normal")
    case state do
      %{error: nil} -> report_ack(state)
      %{error: _error} -> report_fail(state)
    end
    {:noreply, next(state)}
  end

  def handle_info({:EXIT, pid, :killed}, %{worker_pid: worker_pid} = state)
  when pid == worker_pid do
    Logger.debug("Worker stopped :killed")

    report_fail(%{state | error: {"killed", "", ""}})

    {:noreply, next(state)}
  end

  def handle_info({:EXIT, pid, {errtype, trace} = reason}, %{worker_pid: worker_pid} = state)
  when pid == worker_pid do
    Logger.debug("Worker exitted unexpectedly #{inspect(reason)}")

    report_fail(%{state | error: {errtype, inspect(trace), ""}})

    {:noreply, next(state)}
  end

  # Either update state.job to be a map, or nil if no job was available.
  def fetch(%{queues: queues} = state) do
    %{state | job: with_conn(state, &Protocol.fetch(&1, queues))}
  end

  # If no job was fetched, then start the main loop over again.
  def execute(%{job: nil} = state) do
    next(state)
  end

  # If we have a job, then run it in a separate, monitored process and just wait.
  def execute(%{job: job} = state) do
    {:ok, worker_pid} = Executor.start_link(self(), state.middleware)
    GenServer.cast(worker_pid, {:run, job})

    %{"jid" => jid, "jobtype" => jobtype, "args" => args} = job
    Logger.info("S #{inspect(self())} jid-#{jid} (#{jobtype}) #{inspect(args)}")

    %{state | worker_pid: worker_pid, start_time: now_in_ms()}
  end

  # Reset some state and trigger the main loop again.
  def next(state) do
    GenServer.cast(self(), :next)
    %{state | job: nil, worker_pid: nil, error: nil, start_time: nil}
  end

  defp report_ack(%{job: job, start_time: start_time} = state) do
    jid = job["jid"]
    jobtype = job["jobtype"]
    time = elapsed(start_time)

    Logger.info("✓ #{inspect(self())} jid-#{jid} (#{jobtype}) #{time}s")

    {:ok, _} = with_conn(state, &Protocol.ack(&1, jid))
    Logger.debug("ack'ed #{jid}")

    if_test do
      send TestJidPidMap.get(jid), {:report_ack, %{job: job, time: time}}
    end
  end

  defp report_fail(%{job: job, error: error, start_time: start_time} = state) do
    jid = job["jid"]
    jobtype = job["jobtype"]
    time = elapsed(start_time)

    Logger.info("✘ #{inspect(self())} jid-#{jid} (#{jobtype}) #{time}s")

    {errtype, message, trace} = error
    trace = String.split(trace, "\n")
    {:ok, _} = with_conn(state, &Protocol.fail(&1, jid, errtype, message, trace))
    Logger.debug("fail'ed #{jid}")

    if_test do
      send TestJidPidMap.get(jid), {:report_fail, %{job: job, time: time, error: error}}
    end
  end

  defp format_error({errtype, message, trace}) do
    "(#{errtype}) #{message}\n#{trace}"
  end

  defp elapsed(t) do
    ((now_in_ms() - t) / 1000) |> Float.round(3)
  end

  defp with_conn(%{name: pool}, f) do
    try do
      :poolboy.transaction(pool, f)
    catch
      :exit, {:timeout, _} ->
        Logger.warn("connection pool timeout")
        with_conn(%{config_module: pool}, f)
    end
  end

end
