defmodule Faktory.JobTask do
  @moduledoc false
  defstruct [:config, :job, :report_queue, :task, :start_time]

  def run(state) do
    log(:start, state)

    state = %{state |
      task: Task.async(__MODULE__, :perform, [state]),
      start_time: System.monotonic_time(:millisecond)
    }

    # That process that is calling this function needs to trap
    # exits so that the catch clause in the try block works.

    try do
      Task.await(state.task, :infinity)
    catch
      :exit, reason -> handle_exit(state, reason)
    else
      _ -> ack(state)
    end
  end

  def perform(state) do
    job = state.job
    middleware = state.config.middleware

    Faktory.Logger.debug "performing job #{inspect(job)}"

    Faktory.Middleware.traverse(job, middleware, fn job ->
      module = state.config.jobtype_map[ job["jobtype"] ]
      module || raise(Faktory.Error.InvalidJobType, message: job["jobtype"])
      apply(module, :perform, job["args"])
    end)
  end

  defp handle_exit(state, reason) do
    {reason, _task_info} = reason
    task_pid = state.task.pid

    # Clear out our mailbox
    receive do
      {:EXIT, ^task_pid, ^reason} -> nil
    end

    error = Faktory.Error.from_reason(reason)
    fail(state, error)
  end

  defp ack(state) do
    log(:ack, state)
    item = {:ack, state.job["jid"]}
    BlockingQueue.push(state.report_queue, item)
  end

  defp fail(state, error) do
    log(:fail, state)
    item = {:fail, state.job["jid"], error}
    BlockingQueue.push(state.report_queue, item)
  end

  defp log(type, state) do
    pid     = inspect(self())
    jid     = state.job["jid"]
    jobtype = state.job["jobtype"]
    status  = case type do
      :start  -> "S"
      :ack    -> "✓"
      :fail   -> "✘"
    end
    message = "#{status} #{pid} jid-#{jid} (#{jobtype})"

    if type == :start do
      Faktory.Logger.info(message)
    else
      time = elapsed(state)
      Faktory.Logger.info("#{message} #{time}s")
    end
  end

  defp elapsed(state) do
    (System.monotonic_time(:millisecond) - state.start_time) / 1000
  end

end
