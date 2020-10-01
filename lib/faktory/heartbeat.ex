defmodule Faktory.Heartbeat do
  @moduledoc false

  use GenServer

  alias Faktory.Protocol
  require Logger

  @interval 15_000

  def child_spec(config) do
    %{
      id: {config.module, __MODULE__},
      start: {__MODULE__, :start_link, [config]}
    }
  end

  def name(config) do
    Faktory.Registry.name({config.module, __MODULE__})
  end

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: name(config))
  end

  def init(config) do
    Process.send_after(self(), :beat, @interval)
    {:ok, conn} = Faktory.Connection.start_link(config)
    {:ok, %{config: config, conn: conn, quiet: false, stop: false}}
  end

  def handle_info(:beat, state) do
    wid = state.config.wid
    conn = state.conn

    case Protocol.beat(conn, wid) do
      {:ok, signal} when is_map(signal) ->
        Logger.debug("wid-#{wid} Heartbeat #{inspect signal}")
        Process.send_after(self(), :beat, @interval)
        case signal do
          %{"state" => "quiet"} -> send(self(), :quiet)
          %{"state" => "terminate"} -> send(self(), :stop)
        end

      {:ok, %{"state" => "stop"} = signal} ->
        Logger.debug("wid-#{wid} Heartbeat #{inspect signal}")
        send(self(), :stop)
        Process.send_after(self(), :beat, @interval)

      {:ok, signal} ->
        Logger.debug("wid-#{wid} Heartbeat #{signal}")
        Process.send_after(self(), :beat, @interval)

      {:error, reason} ->
        Logger.warn("Network error in heartbeat for wid-#{wid}: #{reason} -- retrying in 1s")
        Process.send_after(self(), :beat, 1000)
    end

    {:noreply, state}
  end

  def handle_info(:quiet, %{quiet: true} = state), do: {:noreply, state}
  def handle_info(:quiet, state) do
    Faktory.Stage.Fetcher.name(state.config) |> GenStage.call(:quiet)
    {:noreply, %{state | quiet: true}}
  end

  def handle_info(:stop, %{stop: true} = state), do: {:noreply, state}
  def handle_info(:stop, state) do
    :init.stop()
    {:noreply, %{state | stop: true}}
  end

end
