defmodule Faktory.JobTask do
  @moduledoc false
  defstruct [:job, :worker_pid, :pid, :start_time, :error]

  def run(job, middleware) do
    jid = job["jid"]
    jobtype = job["jobtype"]

    Faktory.Logger.debug "performing job #{inspect(job)}"
    Faktory.Logger.info "S #{inspect self()} jid-#{jid} (#{jobtype})"

    start_time = System.monotonic_time(:millisecond)
    {pid, _ref} = spawn_monitor(__MODULE__, :perform, [job, middleware])

    %__MODULE__{
      start_time: start_time,
      worker_pid: self(),
      pid: pid,
      job: job
    }
  end

  def perform(job, middleware) do
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
    # receive do
    #   {:EXIT, ^task_pid, ^reason} -> nil
    # end

    error = Faktory.Error.from_reason(reason)
    fail(state, error)
  end

  defp ack(state) do
    log(:ack, state)
    {:ack, state.job["jid"]}
  end

  defp fail(state, error) do
    log(:fail, state)
    {:fail, state.job["jid"], error}
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
