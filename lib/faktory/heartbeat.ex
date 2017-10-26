defmodule Faktory.Heartbeat do
  use GenServer
  require Logger
  alias Faktory.Protocol

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
    end
    Process.send_after(self(), :beat, 15_000) # 15 seconds
    {:noreply, wid}
  end

end
