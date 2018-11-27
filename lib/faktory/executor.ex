defmodule Faktory.Executor do
  @moduledoc false
  use GenServer
  alias Faktory.{Logger, Utils, Middleware}

  def start_link(worker, middleware) do
    GenServer.start_link(__MODULE__, {worker, middleware})
  end

  def init(state) do
    {:ok, state}
  end

  def handle_cast({:run, job}, {worker, middleware}) do
    try do
      perform(job, middleware) # Eventually calls dispatch.
    rescue
      error -> handle_error(System.stacktrace, error, worker)
    end

    {:stop, :normal, nil}
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
