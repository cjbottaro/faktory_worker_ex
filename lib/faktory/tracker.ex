defmodule Faktory.Tracker do
  @moduledoc false

  defmodule Job do
    @moduledoc false
    defstruct [:payload, :fetch_time, :start_time, :worker_pid]
  end

  use GenServer

  def child_spec(config) do
    %{
      id: {config.module, __MODULE__},
      start: {__MODULE__, :start_link, [config]},
      shutdown: config.shutdown_grace_period
    }
  end

  def name(config) do
    Faktory.Registry.name({config.module, __MODULE__, :tracker})
  end

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: name(config))
  end

  def init(config) do
    Faktory.Logger.debug "Tracker stage #{inspect self()} starting up"

    {:ok, conn} = Faktory.Connection.start_link(config)

    state = %{
      config: config,
      conn: conn,
    }

    {:ok, state}
  end

  # Note that that timeout is :infinity. All communication with the Faktory
  # server retries, so there is no point in timing out and trying to continue.

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
