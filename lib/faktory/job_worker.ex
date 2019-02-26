defmodule Faktory.JobWorker do
  @moduledoc false

  defstruct [:config, :job_tasks]

  use GenStage

  def start_link(config, index) do
    name = Faktory.Registry.name({config.module, __MODULE__, index})
    GenStage.start_link(__MODULE__, config, name: name)
  end

  def init(config) do
    # Process.flag(:trap_exit, true) # The secret sauce.
    state = %__MODULE__{config: config, job_tasks: %{}}
    {:producer_consumer, state, subscribe_to: subscribe_to(config)}
  end

  def handle_events([job], _from, state) do
    job_task = Faktory.JobTask.run(job, state.config.middleware)
    state = update_in state.job_tasks, fn job_tasks ->
      Map.put(job_tasks, job_task.pid, job_task)
    end
    {:noreply, [], state}
  end

  def handle_info({:DOWN, _ref, :process, pid, :normal}, state) do
    {job_task, state} = pop_job_task(pid, state)
    {:noreply, [job_task], state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    {job_task, state} = pop_job_task(pid, state)
    job_task = %{job_task | error: Faktory.Error.from_reason(reason)}
    {:noreply, [job_task], state}
  end

  def pop_job_task(pid, state) do
    job_task = Map.fetch!(state.job_tasks, pid) # If the key doesn't exist, we have seriously messed up.
    state = update_in(state.job_tasks, &Map.delete(&1, pid))
    {job_task, state}
  end

  defp subscribe_to(config) do
    producer_name = Faktory.Registry.name({config.module, Faktory.Fetcher})
    [{producer_name, max_demand: 1, min_demand: 0}]
  end

end
