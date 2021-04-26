defmodule Faktory.Stage.Fetcher do
  @moduledoc false

  use GenStage
  require Logger

  def child_spec(config) do
    %{
      id: {__MODULE__, config[:wid]},
      start: {__MODULE__, :start_link, [config]}
    }
  end

  def name(config) do
    {:global, {__MODULE__, config[:wid]}}
  end

  def start_link(config) do
    GenStage.start_link(__MODULE__, config, name: name(config))
  end

  def init(config) do
    queues = Enum.join(config[:queues], ", ")
    Faktory.Logger.debug "Fetcher stage #{inspect self()} starting up -- #{queues}"

    {:ok, conn} = config
    |> Keyword.drop([:name])
    |> Keyword.put(:beat_receiver, self())
    |> Faktory.Connection.start_link()

    state = %{
      config: Map.new(config),
      conn: conn,
      demand: 0,
      errors: 0,
      quiet: false,
      terminate: false,
    }

    {:producer, state}
  end

  # If there is no demand, it means we're idle, so start a fetch loop.
  def handle_demand(1, %{demand: 0} = state) do
    send(self(), :fetch)
    {:noreply, [], %{state | demand: 1}}
  end

  # If there is already demand, we're already in a fetch loop.
  def handle_demand(1, state) do
    {:noreply, [], %{state | demand: state.demand + 1}}
  end

  def handle_info(:fetch, %{quiet: true} = state), do: {:noreply, [], state}

  def handle_info(:fetch, %{terminate: true} = state), do: {:noreply, [], state}

  def handle_info(:fetch, state) do
    %{config: config, conn: conn, demand: demand} = state

    # Blocks for up to two seconds before returning a job or nil.
    case Faktory.Connection.fetch(conn, config.queues) do

      # Job found, send it down the pipeline!
      {:ok, job} when is_map(job) ->
        if demand > 1, do: send(self(), :fetch)
        {:noreply, [job], %{state | demand: demand - 1}}

      # No job found, try again.
      {:ok, nil} ->
        send(self(), :fetch)
        {:noreply, [], state}

      {:error, reason} ->
        time = Faktory.Utils.exp_backoff(state.errors)
        Faktory.Logger.warn("Error during fetch: #{reason} -- retrying in #{time/1000}s")
        Process.send_after(self(), :fetch, time)
        {:noreply, [], %{state | errors: state.errors + 1}}

    end

  end

  def handle_info({:faktory, :beat, :quiet}, state) do
    Logger.debug "Fetcher stage #{inspect self()} quieted -- #{state.demand} demand remaining"
    {:noreply, [], %{state | quiet: true}}
  end

  def handle_info({:faktory, :beat, :terminate}, state) do
    Logger.debug "Fetcher stage #{inspect self()} instructed to terminate -- #{state.demand} demand remaining"
    if not state.terminate do
      Faktory.Worker.name(state.config)
      |> Faktory.Worker.stop()
    end
    {:noreply, [], %{state | terminate: true}}
  end

  def handle_cast(:quiet, state) do
    Logger.debug "Fetcher stage #{inspect self()} quieted -- #{state.demand} demand remaining"
    {:noreply, [], %{state | quiet: true}}
  end

end
