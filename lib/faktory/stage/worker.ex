defmodule Faktory.Stage.Worker do
  @moduledoc false

  use GenStage
  require Logger
  import Faktory.Worker, only: [human_name: 1]

  @reserve_for 1800

  def child_spec(config) do
    %{
      id: {__MODULE__, config[:wid]},
      start: {__MODULE__, :start_link, [config]},
      shutdown: config[:shutdown]
    }
  end

  def name(config) do
    {:global, {__MODULE__, config[:wid]}}
  end

  def start_link(config) do
    GenStage.start_link(__MODULE__, config, name: name(config))
  end

  def init(config) do
    Process.flag(:trap_exit, true) # For graceful shutdown.
    Logger.info "Worker stage for #{human_name(config)} starting up -- #{config[:concurrency]}"

    {:ok, conn} = Keyword.drop(config, [:wid, :name])
    |> Faktory.Connection.start_link()

    state = %{
      config: Map.new(config),
      conn: conn,
      producer: nil,
      tasks: %{},
    }

    {:consumer, state, subscribe_to: [{
      Faktory.Stage.Fetcher.name(state.config),
      min_demand: 0,
      max_demand: 1
    }]}
  end

  # We have to manually manage our demand because
  # we're creating async tasks to do the actual jobs.
  def handle_subscribe(:producer, _opts, from, state) do
    Enum.each(1..state.config.concurrency, fn _ ->
      :ok = GenStage.ask(from, 1)
    end)
    {:manual, %{state | producer: from}}
  end

  def handle_events([job], _from, state) do
    %{config: config, tasks: tasks} = state
    %{middleware: middleware, jobtype_map: jobtype_map} = config

    start_at = monotonic_time()

    task = Task.async(fn ->
      Faktory.Middleware.traverse(job, middleware, fn job ->
        module = jobtype_map[ job.jobtype ]
        module || raise(Faktory.Error.InvalidJobType, message: job.jobtype)
        log_start(job, state)
        apply(module, :perform, job.args)
      end)
    end)

    timeout = (job.reserve_for || @reserve_for) * 1000
    timer = Process.send_after(self(), {:reservation_timeout, task.ref}, timeout)

    task = Map.merge(task, %{start_at: start_at, job: job, timer: timer})
    tasks = Map.put(tasks, task.ref, task)

    {:noreply, [], %{state | tasks: tasks}}
  end

  def handle_info({ref, _value}, state) when is_map_key(state.tasks, ref) do
    %{tasks: tasks, producer: producer} = state

    # Stop :DOWN message from being sent. According to the docs, this is very
    # efficient; more efficient than handling and ignoring the :DOWN message.
    Process.demonitor(ref, [:flush])

    {task, tasks} = Map.pop!(tasks, ref)

    ack(task, state)
    :ok = GenStage.ask(producer, 1)

    {:noreply, [], %{state | tasks: tasks}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) when is_map_key(state.tasks, ref) do
    %{tasks: tasks, producer: producer} = state

    {task, tasks} = Map.pop!(tasks, ref)

    fail(task, reason, state)
    :ok = GenStage.ask(producer, 1)

    {:noreply, [], %{state | tasks: tasks}}
  end

  def handle_info({:reservation_timeout, ref}, state) when is_map_key(state.tasks, ref) do
    %{tasks: tasks, producer: producer} = state

    {task, tasks} = Map.pop!(tasks, ref)

    # If Task.shutdown doesn't return nil, that means that Task finished,
    # so we should be receiving a :DOWN or value message (or already have).
    # We don't need to ack or fail it because Faktory will put the job
    # on retry queue if the reservation expires.
    if Task.shutdown(task, :brutal_kill) == nil do
      log_reservation_expired(task, state)
      :ok = GenStage.ask(producer, 1) # Don't forget this.
    end

    {:noreply, [], %{state | tasks: tasks}}
  end

  # Task.async both links and monitors, so we can ignore the :EXIT messages from
  # the link because we're already handling the :DOWN messages from the monitor.
  def handle_info({:EXIT, _pid, _reason}, state) do
    {:noreply, [], state}
  end

  def terminate(reason, state) do
    %{config: config, tasks: tasks} = state

    count = map_size(tasks)
    Logger.info "Worker stage for #{human_name(config)} shutting down -- #{count} jobs running"

    start_time = monotonic_time()

    # Tell the fetcher to stop fetching.
    :ok = Faktory.Stage.Fetcher.name(config)
    |> GenServer.cast(:quiet)

    Map.values(tasks)
    |> Task.yield_many(config.shutdown - 1_000)
    |> Enum.each(fn
      {task, {:ok, _value}} -> ack(state, task)
      {task, {:exit, error}} -> fail(state, task, error)
      {task, nil} -> case Task.shutdown(task, :brutal_kill) do
        {:ok, _value} -> ack(task, state)
        {:exit, reason} -> fail(task, reason, state)
        nil -> fail(task, reason, state)
      end
    end)

    time = (monotonic_time() - start_time) |> Faktory.Utils.format_duration()

    Logger.info "Worker stage for #{human_name(config)} shutdown -- #{time}"
  end

  def ack(task, state, retries \\ 0) do
    %{conn: conn} = state

    Process.cancel_timer(task.timer)

    case Faktory.Connection.ack(conn, task.job.jid) do
      :ok -> log_ack(task, state)

      {:error, _reason} ->
        Process.send_after(
          self(),
          {:ack_retry, task, retries + 1},
          Faktory.Utils.exp_backoff(retries)
        )
    end
  end

  def fail(task, reason, state, retries \\ 0) do
    %{conn: conn} = state

    Process.cancel_timer(task.timer)

    {errtype, message, trace} = Faktory.Error.down_reason_to_fail_args(reason)

    case Faktory.Connection.fail(conn, task.job.jid, errtype, message, trace) do
      :ok -> log_fail(task, reason, state)

      {:error, _reason} ->
        Process.send_after(
          self(),
          {:ack_retry, task, retries + 1},
          Faktory.Utils.exp_backoff(retries)
        )
    end
  end

  def log_start(job, state) do
    :telemetry.execute(
      [:faktory, :job, :start],
      %{},
      %{job: job, worker: state.config}
    )
  end

  def log_ack(task, state) do
    :telemetry.execute(
      [:faktory, :job, :ack],
      %{usec: elapsed(task.start_at)},
      %{job: task.job, worker: state.config}
    )
  end

  def log_fail(task, reason, state) do
    :telemetry.execute(
      [:faktory, :job, :fail],
      %{usec: elapsed(task.start_at)},
      %{job: task.job, worker: state.config, reason: reason}
    )
  end

  def log_reservation_expired(task, state) do
    :telemetry.execute(
      [:faktory, :job, :timeout],
      %{usec: elapsed(task.start_at)},
      %{job: task.job, worker: state.config}
    )
  end

  defp elapsed(start_at) do
    monotonic_time() - start_at
  end

  defp monotonic_time do
    System.monotonic_time(:microsecond)
  end

end
