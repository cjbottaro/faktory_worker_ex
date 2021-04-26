defmodule Faktory.Stage.Fetcher do
  @moduledoc false

  use GenStage
  require Logger
  import Faktory.Worker, only: [human_name: 1]

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
    Logger.info "Fetcher stage for #{human_name(config)} starting up -- #{inspect config[:queues]}"

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

      # Very subtle race condition. Our fetch returns {:error, :quiet} or
      # {:error, :terminate} before we receive the heartbeat status from our
      # connection.

      # 22:54:39.087 [debug] ->> "FETCH default\r\n" in 74μs
      # 22:54:41.100 [debug] <<- "$-1\r\n" in 2013ms
      # 22:54:41.100 [debug] ->> "FETCH default\r\n" in 34μs
      # 22:54:41.929 [debug] ->> "BEAT {\"rss_kb\":42103,\"wid\":\"6ac5ee0075a56c3b\"}\r\n" in 60μs
      # 22:54:43.110 [debug] <<- "$-1\r\n" in 2009ms
      # 22:54:43.110 [debug] <<- "$17\r\n" in 1180ms
      # 22:54:43.110 [debug] <<- "{\"state\":\"quiet\"}" in 19μs
      # 22:54:43.110 [debug] <<- "\r\n" in 6μs
      # 22:54:43.121 [warn]  Error during fetch: quiet -- retrying in 1.589s

      # It actually doesn't affect anything except for a warning message
      # (triggered by the last condition of this case statement), but we can
      # prevent that by explicitly matching those cases.
      {:error, :quiet} -> {:noreply, [], state}
      {:error, :terminate} -> {:noreply, [], state}

      {:error, reason} ->
        time = Faktory.Utils.exp_backoff(state.errors)
        Logger.warn("Error during fetch: #{reason} -- retrying in #{time/1000}s")
        Process.send_after(self(), :fetch, time)
        {:noreply, [], %{state | errors: state.errors + 1}}

    end

  end

  def handle_info({:faktory, :beat, :quiet}, state) do
    %{config: config, demand: demand} = state

    if not state.quiet do
      Logger.info "Fetcher stage for #{human_name(config)} quieted by UI -- #{config.concurrency - demand} jobs running"
    end

    {:noreply, [], %{state | quiet: true}}
  end

  def handle_info({:faktory, :beat, :terminate}, state) do
    %{config: config, demand: demand} = state

    if not state.terminate do
      Logger.info "Fetcher stage for #{human_name(config)} stopped by UI -- #{config.concurrency - demand} jobs running"
      Faktory.Worker.name(config)
      |> Faktory.Worker.stop()
    end

    {:noreply, [], %{state | terminate: true}}
  end

  def handle_cast(:quiet, state) do
    %{config: config} = state

    if not state.quiet do
      Logger.info "Fetcher stage for #{human_name(config)} quieted by shutdown"
    end

    {:noreply, [], %{state | quiet: true}}
  end

end
