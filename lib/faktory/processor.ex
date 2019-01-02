defmodule Faktory.Processor do
  @moduledoc false
  use GenServer

  alias Faktory.{Logger, Protocol, Executor}
  import Faktory.Utils, only: [now_in_ms: 0, if_test: 1]

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  def init(config) do
    config = Map.new(config)
    {:ok, conn} = Faktory.Connection.start_link(config)

    # Queue up our mailbox.
    GenServer.cast(self(), :next)

    # Get our state in order.
    state = Map.merge(config, %{
      conn: conn,
      job: nil,
      executor_pid: nil,
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
  def handle_call({:error_report, error}, {from, _ref}, %{executor_pid: executor_pid} = state)
  when from == executor_pid do
    Logger.debug("Worker reported an error...\n#{format_error(error)}")
    {:reply, :ok, %{state | error: error}}
  end

  # This gets triggered when the worker process ends. At this point we either
  # have a successully run job or a failure. Either way, we need to restart
  # the main loop.
  def handle_info({:DOWN, _ref, :process, pid, :normal}, %{executor_pid: executor_pid} = state)
  when pid == executor_pid do
    Logger.debug("Worker stopped :normal")
    case state do
      %{error: nil} -> report_ack(state)
      %{error: _error} -> report_fail(state)
    end
    {:noreply, next(state)}
  end

  def handle_info({:DOWN, _ref, :process, pid, :killed}, %{executor_pid: executor_pid} = state)
  when pid == executor_pid do
    Logger.debug("Worker stopped :killed")

    report_fail(%{state | error: {"killed", "", ""}})

    {:noreply, next(state)}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{executor_pid: executor_pid} = state)
  when pid == executor_pid and is_tuple(reason) do
    Logger.debug("Worker stopped :exit")

    # reason is some Erlang tuple. Luckily, Elixir gives us some functions to
    # format it into an exception with trace. Unfortunately, it's a string and
    # we have to parse it into {errtype, message, trace}.
    error = Exception.format_exit(reason) |> parse_format_exit

    report_fail(%{state | error: error})

    {:noreply, next(state)}
  end

  # Either update state.job to be a map, or nil if no job was available.
  def fetch(%{conn: conn, queues: queues} = state) do
    %{state | job: Protocol.fetch(conn, queues)}
  end

  # If no job was fetched, then start the main loop over again.
  def execute(%{job: nil} = state) do
    next(state)
  end

  # If we have a job, then run it in a separate, monitored process and just wait.
  def execute(%{job: job} = state) do
    executor_pid = Process.spawn(Executor, :run, [self(), job, state.middleware], [])
    Process.monitor(executor_pid)

    Logger.debug("executor #{inspect(executor_pid)}")

    %{"jid" => jid, "jobtype" => jobtype, "args" => args} = job
    Logger.info("S #{inspect(self())} jid-#{jid} (#{jobtype}) #{inspect(args)}")

    %{state | executor_pid: executor_pid, start_time: now_in_ms()}
  end

  # Reset some state and trigger the main loop again.
  def next(state) do
    GenServer.cast(self(), :next)
    %{state | job: nil, executor_pid: nil, error: nil, start_time: nil}
  end

  defp report_ack(%{job: job, start_time: start_time} = state) do
    jid = job["jid"]
    jobtype = job["jobtype"]
    time = elapsed(start_time)

    Logger.info("✓ #{inspect(self())} jid-#{jid} (#{jobtype}) #{time}s")

    {:ok, _} = Protocol.ack(state.conn, jid)
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
    {:ok, _} = Protocol.fail(state.conn, jid, errtype, message, trace)
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

  # string looks like this:
  # Task #PID<0.227.0> started from #PID<0.226.0> terminating
  # ** (ArithmeticError) bad argument in arithmetic expression
  #   (faktory_worker_ex) test/support/die_worker.ex:8: anonymous fn/0 in DieWorker.perform/1
  #   (elixir) lib/task/supervised.ex:85: Task.Supervised.do_apply/2
  #   (stdlib) proc_lib.erl:247: :proc_lib.init_p_do_apply/3
  defp parse_format_exit(string) do
    try do
      [_, banner | trace] = String.split(string, "\n")
        |> Enum.map(&String.trim/1)
      [_, errtype, message | []] = String.split(banner, " ", parts: 3)
      errtype = errtype
        |> String.trim_leading("(")
        |> String.trim_trailing(")")
      trace = Enum.join(trace, "\n")
      {errtype, message, trace}
    rescue
      _ ->
        Logger.error("Failed to parse error message:\n#{string}")
        {"<internal_error>", "see logs", ""}
    end
  end

end
