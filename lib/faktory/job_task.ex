defmodule Faktory.JobTask do
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
      {error, trace} -> if Exception.exception?(error) do
        handle_exception(state, error, trace)
      else
        handle_error(state, reason)
      end
      reason -> handle_exit_reason(state, reason)
    end
  end

  defp handle_exception(state, exception, trace) do
    trace = Exception.format_stacktrace(trace)
    |> String.split("\n")
    |> Enum.map(&String.replace_leading(&1, " ", ""))

    fail(state,
      errtype: exception.__struct__ |> inspect,
      message: Exception.message(exception),
      trace: trace
    )
  end

  defp handle_error(state, reason) do
    lines = Exception.format_exit(reason)
    |> String.split("\n")
    |> Enum.map(&String.replace_leading(&1, " ", ""))

    [_trash, type | trace] = lines
    [_trace, errtype, message] = String.split(type, " ", parts: 3)

    errtype = String.replace_prefix(errtype, "(", "")
    errtype = String.replace_suffix(errtype, ")", "")

    fail(state,
      errtype: errtype,
      message: message,
      trace: trace
    )
  end

  defp handle_exit_reason(state, reason) do
    fail(state, errtype: "exit", message: inspect(reason))
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
