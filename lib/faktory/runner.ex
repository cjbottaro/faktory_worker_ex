defmodule Faktory.Runner do
  @moduledoc false

  use GenStage

  def start_link(config, index) do
    name = Faktory.Registry.name({config.module, __MODULE__, index})
    GenStage.start_link(__MODULE__, {config, index}, name: name)
  end

  def init({config, index}) do
    Faktory.Logger.debug "Worker stage #{inspect self()} starting up"
    Process.flag(:trap_exit, true) # For shutdown grace period, see supervisor.
    {:producer_consumer, config, subscribe_to: subscribe_to(config, index)}
  end

  # I originally tried returning [] here and emitting the events asynchronously in
  # handle_info/2 callbacks. That doesn't work because by default, GenStage will
  # send demand immediately after this function returns. It's a big pain to go into
  # manual mode and manage subscriptions/demand youself, so we're just going to do the
  # work synchonously here.
  def handle_events([job], _from, config) do
    jid = job["jid"]
    args = job["args"]
    jobtype = job["jobtype"]
    middleware = config.middleware
    jobtype_map = config.jobtype_map

    Faktory.Logger.info "START 🚀 #{inspect self()} jid-#{jid} (#{jobtype}) #{inspect args}"

    # I should probably make this a struct, but it seems weird to have a module without any
    # functions... that's probably just OO brain damage over the years.
    report = %{
      start_time: System.monotonic_time(:millisecond),
      worker_pid: self(),
      job: job,
      error: nil
    }

    {pid, ref} = spawn_monitor fn ->
      Faktory.Middleware.traverse(job, middleware, fn job ->
        module = jobtype_map[ job["jobtype"] ]
        module || raise(Faktory.Error.InvalidJobType, message: job["jobtype"])
        apply(module, :perform, job["args"])
      end)
    end

    # Block until job is finished. If there is an error, update our report.
    report = receive do
      {:DOWN, ^ref, :process, ^pid, :normal} ->
        %{report | error: nil}
      {:DOWN, ^ref, :process, ^pid, reason} ->
        %{report | error: Faktory.Error.from_reason(reason)}
    end

    {:noreply, [report], config}
  end

  def terminate(_reason, _state) do
    Faktory.Logger.debug "Worker stage #{inspect self()} shutting down"
  end

  # I'm not sure why, but each job worker cannot subscribe to all the fetchers. I think it
  # has something to do with how demand works, but if you have 2 fetchers, 4 job workers,
  # and enqueue 4 jobs, then 4 jobs get fetched immediately, but only two of them are processed
  # at a time, and only by job workers 1-2. You have to enqueue 8 jobs in order to
  # get job workers 3-4 to "wake up".
  #
  # Simple solution is to say job workers 1-2 subscribe to fetcher 1, while job workers 3-4
  # subscribe to fetcher 2.
  defp subscribe_to(config, index) do
    fetcher_index = rem(index, config.fetcher_count) + 1
    fetcher_name = Faktory.Fetcher.name(config, fetcher_index)
    [{fetcher_name, max_demand: 1, min_demand: 0}]
  end

end
