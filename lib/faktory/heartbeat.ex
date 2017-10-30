defmodule Faktory.Heartbeat do
  @moduledoc false
  use GenServer
  alias Faktory.{Logger, Protocol}
  import Faktory.Utils, only: [stringify: 1]

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  def init(config) do
    %{name: pool, wid: wid} = config

    # Make sure we beat at least once before starting the workers.
    beat(pool, wid)

    # Start the timer.
    Process.send_after(self(), :beat, 15_000) # 15 seconds

    {:ok, {pool, wid}}
  end

  def handle_info(:beat, {pool, wid}) do
    beat(pool, wid)
    Process.send_after(self(), :beat, 15_000) # 15 seconds
    {:noreply, {pool, wid}}
  end

  defp beat(pool, wid) do
    case :poolboy.transaction(pool, &Protocol.beat(&1, wid)) do
      :ok -> Logger.debug("wid-#{wid} Heartbeat ok")
      {:ok, signal} -> Logger.debug("wid-#{wid} Heartbeat #{signal}")
      {:error, reason} -> Logger.warn("wid-#{wid} Heartbeat ERROR: #{stringify(reason)}")
    end
  end


end
