defmodule Faktory.Stage.Worker do
  @moduledoc false

  use GenStage

  def child_spec({config, index}) do
    %{
      id: {config.module, __MODULE__, index},
      start: {__MODULE__, :start_link, [config, index]},
      shutdown: config.shutdown_grace_period
    }
  end

  def name(config, index) do
    Faktory.Registry.name({config.module, __MODULE__, index})
  end

  def start_link(config, index) do
    GenStage.start_link(__MODULE__, config, name: name(config, index))
  end

  def init(config) do
    Process.flag(:trap_exit, true) # For shutdown grace period, see supervisor.
    Faktory.Logger.debug "Worker stage #{inspect self()} starting up"
    state = %{config: config, tracker: Faktory.Tracker.name(config)}
    {:consumer, state} # Delay producer subscription until fetcher signals it's ready.
  end

  def handle_cast(:subscribe, state) do
    :ok = GenStage.async_subscribe(self(),
      to: Faktory.Stage.Fetcher.name(state.config),
      min_demand: 0,
      max_demand: 1
    )
    {:noreply, [], state}
  end

  def handle_events([job], _from, state) do
    import Faktory.Utils, only: [if_test: 1]

    jid = job["jid"]
    middleware = state.config.middleware
    jobtype_map = state.config.jobtype_map

    :ok = Faktory.Tracker.start(state.tracker, jid)

    {pid, ref} = spawn_monitor fn ->
      Faktory.Middleware.traverse(job, middleware, fn job ->
        module = jobtype_map[ job["jobtype"] ]
        module || raise(Faktory.Error.InvalidJobType, message: job["jobtype"])
        apply(module, :perform, job["args"])
      end)
    end

    # Block until job is finished.
    receive do
      {:DOWN, ^ref, :process, ^pid, :normal} ->
        :ok = Faktory.Tracker.ack(state.tracker, jid)
        if_test do: test_results(jid)
      {:DOWN, ^ref, :process, ^pid, reason} ->
        :ok = Faktory.Tracker.fail(state.tracker, jid, reason)
        if_test do: test_results(jid, reason)
    end

    {:noreply, [], state}
  end

  def terminate(_reason, _state) do
    Faktory.Logger.debug "Worker stage #{inspect self()} shutting down"
  end

  defp test_results(jid, reason \\ nil) do
    error = reason && Faktory.Error.from_reason(reason)
    send TestJidPidMap.get(jid), %{jid: jid, error: error}
  end

end
