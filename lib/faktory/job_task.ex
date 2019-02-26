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

end
