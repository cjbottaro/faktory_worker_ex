defmodule Faktory.Heartbeat do
  @moduledoc false

  alias Faktory.{Logger, Protocol}
  import Faktory.Utils, only: [stringify: 1]

  def start_link(config) do
    Task.start_link(__MODULE__, :run, [config])
  end

  def run(config) do
    {:ok, conn} = Faktory.Connection.start_link(config)
    Stream.interval(15_000)
    |> Enum.each(fn _ -> beat(config, conn) end)
  end

  def beat(config, conn) do
    wid = config.wid

    case Protocol.beat(conn, wid) do
      :ok -> Logger.debug("wid-#{wid} Heartbeat ok")
      {:ok, signal} -> Logger.debug("wid-#{wid} Heartbeat #{signal}")
      {:error, reason} -> Logger.warn("wid-#{wid} Heartbeat ERROR: #{stringify(reason)}")
    end
  end

end
