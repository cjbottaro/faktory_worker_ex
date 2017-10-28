defmodule Faktory.Manager do
  @moduledoc false
  use GenServer

  alias Faktory.{Logger, Protocol, Worker}
  import Faktory.Utils, only: [now_in_ms: 0]

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  def init(config) do
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
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{worker_pid: worker_pid} = state)
  when pid == worker_pid do
    Logger.debug("Worker stopped #{inspect(reason)}") # This better not be anything other than :normal!
    case state do
      %{error: nil} -> report_ack(state)
      %{error: _error} -> report_fail(state)
    end
    {:noreply, next(state)}
  end

  # Either update state.job to be a map, or nil if no job was available.
  def fetch(%{queues: queues} = state) do
    %{state | job: with_conn(&Protocol.fetch(&1, queues))}
  end

  # If no job was fetched, then start the main loop over again.
  def execute(%{job: nil} = state) do
    next(state)
  end

  # If we have a job, then run it in a separate, monitored process and just wait.
  def execute(%{job: job} = state) do
    {:ok, worker_pid} = Worker.start_link(self(), state.middleware)
    Process.monitor(worker_pid)
    GenServer.cast(worker_pid, {:run, job})

    %{"jid" => jid, "jobtype" => jobtype, "args" => args} = job
    Logger.info("#{inspect(self())} jid-#{jid} started (#{jobtype}) #{inspect(args)}")

    %{state | worker_pid: worker_pid, start_time: now_in_ms()}
  end

  # Reset some state and trigger the main loop again.
  def next(state) do
    GenServer.cast(self(), :next)
    %{state | job: nil, worker_pid: nil, error: nil, start_time: nil}
  end

  defp report_ack(%{job: job, start_time: start_time}) do
    jid = job["jid"]

    Logger.info("#{inspect(self())} jid-#{jid} succeeded in #{elapsed(start_time)}s")

    {:ok, _} = with_conn(&Protocol.ack(&1, jid))
    Logger.debug("ack'ed #{jid}")
  end

  defp report_fail(%{job: job, error: error, start_time: start_time}) do
    jid = job["jid"]

    Logger.info("#{inspect(self())} jid-#{jid} failed in #{elapsed(start_time)}s")

    {errtype, message, trace} = error
    trace = String.split(trace, "\n")
    {:ok, _} = with_conn(&Protocol.fail(&1, jid, errtype, message, trace))
    Logger.debug("failed #{jid}")
  end

  defp format_error({errtype, message, trace}) do
    "(#{errtype}) #{message}\n#{trace}"
  end

  defp elapsed(t) do
    ((now_in_ms() - t) / 1000) |> Float.round(3)
  end

  defp with_conn(f) do
    :poolboy.transaction(Faktory.worker_config_module, f)
  end

end
