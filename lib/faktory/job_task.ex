defmodule Faktory.JobTask do
  defstruct [:config, :job, :report_queue, :task, :start_time]

  def run(state) do
    state = %{state |
      task: Task.async(__MODULE__, :perform, [state]),
      start_time: System.monotonic_time(:millisecond)
    }

    # That process that is calling this function needs to trap
    # exits so that the catch clause in the try block works.

    try do
      Task.await(state.task)
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
      try do
        Module.safe_concat(Elixir, job["jobtype"])
      rescue
        ArgumentError -> raise Faktory.Error.InvalidJobType, message: job["jobtype"]
      else
        module -> apply(module, :perform, job["args"])
      end
    end)
  end

  defp handle_exit(state, reason) do
    {reason, _task_info} = reason
    task_pid = state.task.pid

    # Clear out our mailbox
    receive do
      {:EXIT, ^task_pid, ^reason} -> nil
    end

    case reason do
      {exception, trace} -> handle_exception(state, exception, trace)
      :killed -> handle_killed(state)
      value -> handle_unknown(state, value)
    end
  end

  defp handle_exception(state, exception, trace) do
    fail(state,
      errtype: exception.__struct__ |> inspect,
      message: Exception.message(exception),
      trace: Exception.format_stacktrace(trace)
    )
  end

  defp handle_killed(state) do
    fail(state, errtype: ":killed")
  end

  defp handle_unknown(state, value) do
    fail(state, errtype: ":unknown", trace: inspect(value))
  end

  defp ack(state) do
    log(:ack, state)
    item = {:ack, state.job["jid"]}
    BlockingQueue.push(state.report_queue, item)
  end

  defp fail(state, reason) do
    log(:fail, state)
    item = {:fail, state.job["jid"], reason}
    BlockingQueue.push(state.report_queue, item)
  end

  defp log(type, state) do
    pid     = inspect(self())
    jid     = state.job["jid"]
    jobtype = state.job["jobtype"]
    time    = elapsed(state)
    message = case type do
      :ack -> "✓"
      :fail -> "✘"
    end
    Faktory.Logger.info("#{message} #{pid} jid-#{jid} (#{jobtype}) #{time}s")
  end

  defp elapsed(state) do
    (System.monotonic_time(:millisecond) - state.start_time) / 1000
  end

end
