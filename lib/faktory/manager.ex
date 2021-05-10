defmodule Faktory.Manager do
  @moduledoc false

  use GenServer

  alias Faktory.{Logger, Protocol}

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
    Faktory.Logger.debug "Manager #{inspect self()} starting up"
    Process.send_after(self(), :beat, @interval)
    {:ok, conn} = Faktory.Connection.start_link(config)
    {:ok, %{config: config, conn: conn, quiet: false, stop: false}}
  end

  def ack(server, jid) do
    GenServer.call(server, {:ack, jid}, :infinity)
  end

  def fail(server, jid, reason) do
    GenServer.call(server, {:fail, jid, reason}, :infinity)
  end

  def handle_call({:ack, jid}, _from, state) do
    retry_until_ok("ACK", fn -> Faktory.Protocol.ack(state.conn, jid) end)
    {:reply, :ok, state}
  end

  def handle_call({:fail, jid, reason}, _from, state) do
    %{errtype: errtype, message: message, trace: trace} = Faktory.Error.from_reason(reason)
    retry_until_ok("FAIL", fn -> Faktory.Protocol.fail(state.conn, jid, errtype, message, trace) end)
    {:reply, :ok, state}
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

  defp retry_until_ok(cmd, f) do
    Stream.repeatedly(f)
    |> Enum.reduce_while(0, fn

      # Everything went smoothly.
      {:ok, "OK"}, _count ->
        {:halt, :ok}

      # Server error. Log and move on.
      {:ok, {:error, reason}}, _count ->
        Faktory.Logger.warn("Server error on #{cmd}: #{reason} -- moving on")
        {:halt, :ok}

      # Network error. Log, sleep, and retry.
      {:error, reason}, count ->
        time = Faktory.Utils.exp_backoff(count)
        Faktory.Logger.warn("Network error on #{cmd}: #{reason} -- retrying in #{time/1000}s")
        Process.sleep(time)
        {:cont, count+1}
    end)
  end

end
