defmodule Faktory.Executor do
  alias Faktory.{Logger, Utils, Middleware}

  def run(processor, job, middleware) do
    try do
      perform(job, middleware)
    rescue
      error -> handle_error(System.stacktrace, error, processor)
    end
  end

  defp perform(job, middleware) do
    Logger.debug "running job #{inspect(job)}"
    Middleware.traverse(job, middleware, fn job ->
      module = Module.safe_concat(Elixir, job["jobtype"])
      apply(module, :perform, job["args"])
    end)
  end

  defp handle_error(trace, error, worker) do
    errtype = Utils.module_name(error.__struct__)
    message = Exception.message(error)
    trace = Exception.format_stacktrace(trace)
    error = {errtype, message, trace}
    :ok = GenServer.call(worker, {:error_report, error})
  end

end
