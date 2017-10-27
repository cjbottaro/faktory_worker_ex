defmodule Faktory.Worker do
  @moduledoc false
  use GenServer
  require Logger

  def start_link(manager, middleware) do
    GenServer.start_link(__MODULE__, {manager, middleware})
  end

  def init(state) do
    {:ok, state}
  end

  def handle_cast({:run, job}, {manager, middleware}) do
    try do
      perform(job, middleware) # Eventually calls dispatch.
    rescue
      error -> handle_error(error, manager)
    end

    {:stop, :normal, nil}
  end

  defp perform(job, middleware) do
    Logger.debug "running job #{inspect(job)}"
    traverse_middleware(job, middleware)
  end

  def dispatch(job) do
    module = Module.safe_concat(Elixir, job["jobtype"])
    apply(module, :perform, job["args"])
  end

  defp handle_error(error, manager) do
    errtype = error.__struct__
      |> Module.split # Gets rid of the Elixir. prefix.
      |> Enum.join(".")
    message = Exception.message(error)
    trace = Exception.format_stacktrace(System.stacktrace)
    error = {errtype, message, trace}
    :ok = GenServer.call(manager, {:error_report, error})
  end

  def traverse_middleware(job, []) do
    dispatch(job)
    job
  end

  def traverse_middleware(job, [middleware | chain]) do
    middleware.call(job, chain, &traverse_middleware/2)
  end

end
