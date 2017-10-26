defmodule Faktory.Worker do
  use GenServer
  require Logger

  def start_link(manager) do
    GenServer.start_link(__MODULE__, manager)
  end

  def init(manager) do
    {:ok, manager}
  end

  def handle_cast({:run, job}, manager) do
    try do
      dispatch(job)
    rescue
      error -> handle_error(error, manager)
    end

    {:stop, :normal, nil}
  end

  defp dispatch(job) do
    Logger.debug "running job #{inspect(job)}"
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

end
