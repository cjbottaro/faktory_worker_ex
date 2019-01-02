defmodule Faktory.Heartbeat do
  @moduledoc false
  use GenServer
  alias Faktory.{Logger, Protocol}
  import Faktory.Utils, only: [stringify: 1]

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  def init(config) do
    config = Map.new(config)

    {:ok, conn} = Faktory.Connection.start_link(config)

    # # Make sure we beat at least once before starting the workers.
    # beat(conn, config.wid)

    # Start the timer.
    Process.send_after(self(), :beat, 15_000) # 15 seconds

    {:ok, {conn, config.wid}}
  end

  def handle_info(:beat, {conn, wid}) do
    beat(conn, wid)
    Process.send_after(self(), :beat, 15_000) # 15 seconds
    {:noreply, {conn, wid}}
  end

  defp beat(conn, wid) do
    case Protocol.beat(conn, wid) do
      :ok -> Logger.debug("wid-#{wid} Heartbeat ok")
      {:ok, signal} -> Logger.debug("wid-#{wid} Heartbeat #{signal}")
      {:error, reason} -> Logger.warn("wid-#{wid} Heartbeat ERROR: #{stringify(reason)}")
    end
  end


end
