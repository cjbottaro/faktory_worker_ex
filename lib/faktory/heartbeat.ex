defmodule Faktory.Heartbeat do
  @moduledoc false
  use GenServer
  alias Faktory.{Logger, Protocol}
  import Faktory.Utils, only: [stringify: 1]

  def start_link(wid) do
    GenServer.start_link(__MODULE__, wid)
  end

  def init(wid) do
    send(self(), :beat)
    {:ok, wid}
  end

  def handle_info(:beat, wid) do
    case Faktory.with_conn(&Protocol.beat(&1, wid)) do
      :ok -> Logger.debug("wid-#{wid} Heartbeat ok")
      {:ok, signal} -> Logger.debug("wid-#{wid} Heartbeat #{signal}")
      {:error, reason} -> Logger.warn("wid-#{wid} Heartbeat ERROR: #{stringify(reason)}")
    end
    Process.send_after(self(), :beat, 15_000) # 15 seconds
    {:noreply, wid}
  end

end
