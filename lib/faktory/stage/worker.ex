defmodule Faktory.Stage.Worker do
  @moduledoc false

  use GenStage
  require Logger
  import Faktory.Utils, only: [if_test: 1]

  @start_status "S 🚀"
  @ack_status   "A 🥂"
  @fail_status  "F 💥"

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
      tracker: Faktory.Tracker.name(config),
      producer: nil,
      jobs: %{},
    }

    {:consumer, state, subscribe_to: [{
      Faktory.Stage.Fetcher.name(state.config),
      min_demand: 0,
      max_demand: 1
    }]}
  end

  def handle_subscribe(:producer, _opts, from, state) do
    Enum.each(1..state.config.concurrency, fn _ ->
      :ok = GenStage.ask(from, 1)
    end)
    state = %{state | producer: from}
    {:manual, state}
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

    Process.send_after(self(), {:reservation_timeout, task.pid}, job["reserve_for"] * 1000)

    task = Map.merge(task, %{start_time: start_time, job: job})
    state = update_in(state.jobs, &Map.put(&1, task.pid, task))

    {:noreply, [], state}
  end

  def handle_info({:EXIT, pid, :normal}, state) do
    case Map.pop(state.jobs, pid) do
      {nil, _jobs} -> {:noreply, [], state}
      {task, jobs} ->
        :ok = Faktory.Tracker.ack(state.tracker, task.job["jid"])
        :ok = GenStage.ask(state.producer, 1)
        log_ack(task)
        if_test do: test_results(task.job["jid"])
        {:noreply, [], put_in(state.jobs, jobs)}
    end
  end

  def handle_info({:EXIT, pid, reason}, state) do
    case Map.pop(state.jobs, pid) do
      {nil, _jobs} -> {:noreply, [], state}
      {task, jobs} ->
        :ok = Faktory.Tracker.fail(state.tracker, task.job["jid"], reason)
        :ok = GenStage.ask(state.producer, 1)
        log_fail(task)
        if_test do: test_results(task.job["jid"], reason)
        {:noreply, [], put_in(state.jobs, jobs)}
    end
  end

  def handle_info({:reservation_timeout, pid}, state) do
    {task, jobs} = Map.pop(state.jobs, pid)
    if task && Task.shutdown(task, :brutal_kill) == nil do
      Logger.info("Reservation expired: " <> task.job["jid"])
      :ok = GenStage.ask(state.producer, 1)
    end
    {:noreply, [], put_in(state.jobs, jobs)}
  end

  # Task.async both links and monitors, so we can ignore the :DOWN messages from
  # the monitor because we're already handling the :EXIT messages from the link.
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, [], state}
  end

  # Tasks report their return value which we can ignore.
  def handle_info({ref, _value}, state) when is_reference(ref) do
    {:noreply, [], state}
  end

  def terminate(reason, state) do
    Faktory.Logger.debug "Worker stage #{inspect self()} shutting down"

    Map.values(state.jobs)
    |> Task.yield_many(state.config.shutdown_grace_period)
    |> Enum.each(fn
      {task, {:ok, _value}} ->
        :ok = Faktory.Tracker.ack(state.tracker, task.job["jid"])
        log_ack(task)

      {task, {:exit, reason}} ->
        :ok = Faktory.Tracker.fail(state.tracker, task.job["jid"], reason)
        log_fail(task)

      {task, nil} ->
        Task.shutdown(task, :brutal_kill)
        :ok = Faktory.Tracker.fail(state.tracker, task.job["jid"], reason)
        log_fail(task)
    end)
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

  if_test do
    defp test_results(jid, reason \\ nil) do
      error = reason && Faktory.Error.from_reason(reason)
      send TestJidPidMap.get(jid), %{jid: jid, error: error}
    end
  end

end
