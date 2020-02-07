# The gist of this is keep track of all workers. On sigterm, notify them and
# shutdown once all of them have reported they have stopped. Also there is
# a configurable shutdown timeout in case of long running jobs.
defmodule Faktory.SignalHandler do
  @moduledoc false

  def register_worker do
    :gen_event.call(:erl_signal_server, Faktory.SignalHandler, {:register, self()})
  end

  def deregister_worker do
    :gen_event.call(:erl_signal_server, Faktory.SignalHandler, {:deregister, self()})
  end

  def init(_) do
    {:ok, MapSet.new}
  end

  def handle_call({:register, pid}, state) do
    {:ok, :ok, MapSet.put(state, pid)}
  end

  def handle_call({:deregister, pid}, state) do
    state = MapSet.delete(state, pid)
    if MapSet.size(state) == 0 do
      Faktory.Logger.info "All processes finished, bye!"
      :init.stop
    end
    {:ok, :ok, state}
  end

  def handle_info(:timeout, state) do
    Faktory.Logger.warn "Shutdown timeout exceeded, stopping now."
    :init.stop
    {:ok, state}
  end

  def handle_event(:sigterm, state) do
    count = MapSet.size(state)

    if count == 0 do
      :init.stop
    else
      Faktory.Logger.info "Caught SIGTERM, asking #{count} processes to finish."
      Enum.each state, &GenStage.cast(&1, :shutdown)
      shutdown_timeout = Application.get_env(:faktory_worker_ex, :shutdown_timeout, 25_000)
      Process.send_after(self(), :timeout, shutdown_timeout)
    end

    {:ok, state}
  end

end
