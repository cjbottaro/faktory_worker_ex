defmodule Faktory.Stage.Fetcher do
  @moduledoc false

  defstruct [:config, :conn, :error_count, :quiet]

  use GenStage

  def queues(config) do
    if config.priority_queues do
      [Enum.join(config.queues, " ")]
    else
      config.queues
    end
  end

  def child_spec({config, queue}) do
    %{
      id: {config.module, __MODULE__, queue},
      start: {__MODULE__, :start_link, [config, queue]}
    }
  end

  def name(config, queue) do
    Faktory.Registry.name({config.module, __MODULE__, queue})
  end

  def names(config) do
    Enum.map(queues(config), &name(config, &1))
  end

  def start_link(config, queue) do
    GenStage.start_link(__MODULE__, config, name: name(config, queue))
  end

  def init(config) do
    queues = Enum.join(config.queues, ", ")
    Faktory.Logger.debug "Fetcher stage #{inspect self()} starting up -- #{queues}"
    {:ok, conn} = Faktory.Connection.start_link(config)

    state = %__MODULE__{
      config: config,
      conn: conn,
      error_count: 0,
      quiet: false
    }

    {:producer, state}
  end

  # If we've been quieted, don't fetch anything.
  def handle_demand(1, %{quiet: true} = state), do: {:noreply, [], state}

  def handle_demand(1, state) do
    conn = state.conn
    queues = state.config.queues

    # Blocks for up to two seconds before returning a job or nil.
    case Faktory.Protocol.fetch(conn, queues) do

      # Job found, send it down the pipeline!
      {:ok, %{} = job} ->
        {:noreply, [job], state}

      # No job found, manually trigger demand since consumers
      # only ask once until they get something.
      {:ok, nil} ->
        send(self(), {:demand, 1})
        {:noreply, [], state}

      # Server error. Report and try again, I guess.
      {:ok, {:error, reason}} ->
        Faktory.Logger.warn("Server error during fetch: #{reason} -- retrying immediately")
        send(self(), {:demand, 1})
        {:noreply, [], state}

      # Network error. Log, sleep, and try again.
      {:error, reason} ->
        time = Faktory.Utils.exp_backoff(state.error_count)
        Faktory.Logger.warn("Network error during fetch: #{reason} -- retrying in #{time/1000}s")
        Process.send_after(self(), {:demand, 1}, time)
        {:noreply, [], state}
    end

  end

  def handle_info({:demand, 1}, state) do
    handle_demand(1, state)
  end

  def handle_call(:quiet, _from, state) do
    Faktory.Logger.info("Fetcher #{inspect self()} silenced")
    {:reply, :ok, [], %{state | quiet: true}}
  end

end
