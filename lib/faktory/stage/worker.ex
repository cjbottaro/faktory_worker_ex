defmodule Faktory.Stage.Worker do
  @moduledoc false

  use GenStage
  require Logger
  import Faktory.Utils, only: [if_test: 1]

  @start_status   "S 🚀"
  @ack_status     "A 🥂"
  @fail_status    "F 💥"
  @reserve_status "R ⏱"

  def child_spec(config) do
    %{
      id: {config.module, __MODULE__},
      start: {__MODULE__, :start_link, [config]},
      shutdown: config.shutdown_grace_period + 1000
    }
  end

  def name(config) do
    Faktory.Registry.name({config.module, __MODULE__})
  end

  def start_link(config) do
    GenStage.start_link(__MODULE__, config, name: name(config))
  end

  def init(config) do
    Process.flag(:trap_exit, true) # For shutdown grace period, see supervisor.
    Faktory.Logger.debug "Worker stage #{inspect self()} starting up (#{config.concurrency})"

    state = %{
      config: config,
      manager: Faktory.Manager.name(config),
      producer: nil,
      jobs: %{},
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
    middleware = state.config.middleware
    jobtype_map = state.config.jobtype_map
    start_time = System.monotonic_time(:millisecond)
    worker_pid = self()

    task = Task.async(fn ->
      Faktory.Middleware.traverse(job, middleware, fn job ->
        module = jobtype_map[ job["jobtype"] ]
        module || raise(Faktory.Error.InvalidJobType, message: job["jobtype"])
        log_start(job, worker_pid)
        apply(module, :perform, job["args"])
      end)
    end)

    timer = Process.send_after(self(), {:reservation_timeout, task.ref}, reserve_for(job) * 1000)

    task = Map.merge(task, %{start_time: start_time, job: job, timer: timer})
    state = update_in(state.jobs, &Map.put(&1, task.ref, task))

    {:noreply, [], state}
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, state) do
    case Map.pop(state.jobs, ref) do
      {nil, _jobs} -> {:noreply, [], state}
      {task, jobs} ->
        :ok = ack(state, task)
        :ok = GenStage.ask(state.producer, 1)
        {:noreply, [], put_in(state.jobs, jobs)}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.pop(state.jobs, ref) do
      {nil, _jobs} -> {:noreply, [], state}
      {task, jobs} ->
        :ok = fail(state, task, reason)
        :ok = GenStage.ask(state.producer, 1)
        {:noreply, [], put_in(state.jobs, jobs)}
    end
  end

  # If Task.shutdown doesn't return nil, that means that Task finished,
  # so we should be receiving a :EXIT/:DOWN message (or already have).
  # We don't need to ack or fail it because Faktory will put the job
  # on retry queue if the reservation expires.
  def handle_info({:reservation_timeout, ref}, state) do
    {task, jobs} = Map.pop(state.jobs, ref)
    if task && Task.shutdown(task, :brutal_kill) == nil do
      log_reservation_expired(task)
      :ok = GenStage.ask(state.producer, 1) # Don't forget this.
    end
    {:noreply, [], put_in(state.jobs, jobs)}
  end

  # Task.async both links and monitors, so we can ignore the :EXIT messages from
  # the link because we're already handling the :DOWN messages from the monitor.
  def handle_info({:EXIT, _pid, _reason}, state) do
    {:noreply, [], state}
  end

  # Tasks report their return value which we can ignore.
  def handle_info({ref, _value}, state) when is_reference(ref) do
    {:noreply, [], state}
  end

  def terminate(reason, state) do
    count = map_size(state.jobs)
    Faktory.Logger.debug "Worker stage #{inspect self()} shutting down -- #{count} jobs running"

    Map.values(state.jobs)
    |> Task.yield_many(state.config.shutdown_grace_period)
    |> Enum.each(fn
      {task, {:ok, _value}} -> ack(state, task)
      {task, {:exit, error}} -> fail(state, task, error)
      {task, nil} -> case Task.shutdown(task, :brutal_kill) do
        {:ok, _value} -> ack(state, task)
        {:exit, error} -> fail(state, task, error)
        nil -> fail(state, task, reason)
      end
    end)
  end

  def ack(state, task) do
    :ok = Faktory.Manager.ack(state.manager, task.job["jid"])
    Process.cancel_timer(task.timer)
    log_ack(task)
    if_test do: test_results(task.job["jid"])
    :ok
  end

  def fail(state, task, reason) do
    :ok = Faktory.Manager.fail(state.manager, task.job["jid"], reason)
    Process.cancel_timer(task.timer)
    log_fail(task)
    if_test do: test_results(task.job["jid"], reason)
    :ok
  end

  def log_start(job, worker_pid) do
    %{"jid" => jid, "jobtype" => jobtype, "args" => args} = job
    args = Faktory.Utils.args_to_string(args)
    Faktory.Logger.info "#{@start_status} #{inspect worker_pid} jid-#{jid} (#{jobtype}) #{args}"
  end

  def log_ack(task) do
    %{"jid" => jid, "jobtype" => jobtype} = task.job
    time = Faktory.Utils.elapsed(task.start_time)
    Faktory.Logger.info "#{@ack_status} #{inspect self()} jid-#{jid} (#{jobtype}) #{time}s"
  end

  def log_fail(task) do
    %{"jid" => jid, "jobtype" => jobtype} = task.job
    time = Faktory.Utils.elapsed(task.start_time)
    Faktory.Logger.info "#{@fail_status} #{inspect self()} jid-#{jid} (#{jobtype}) #{time}s"
  end

  def log_reservation_expired(task) do
    %{"jid" => jid, "jobtype" => jobtype} = task.job
    time = Faktory.Utils.elapsed(task.start_time)
    Faktory.Logger.info "#{@reserve_status} #{inspect self()} jid-#{jid} (#{jobtype}) #{time}s"
  end

  # Some misbehaved clients do not add reserver_for
  @default_reserve_for 1800
  defp reserve_for(job) do
    case job["reserve_for"] do
      nil -> @default_reserve_for
      n when is_integer(n) -> n
      any ->
        jid = job["jid"]
        Faktory.Logger.warn("jid-#{jid} does not have a valid reserve_for: #{inspect any}")
        @default_reserve_for
    end
  end

  if_test do
    defp test_results(jid, reason \\ nil) do
      error = reason && Faktory.Error.from_reason(reason)
      send TestJidPidMap.get(jid), %{jid: jid, error: error}
    end
  end

end
