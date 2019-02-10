defmodule Faktory.Producer do
  defstruct [:config, :job_queue, :conn, :errors]

  def start_link(config) do
    Task.start_link(__MODULE__, :run, [config])
  end

  def run(config) do
    {:ok, conn} = Faktory.Connection.start_link(config)
    job_queue = Faktory.Registry.name(config.module, :job_queue)

    state = %__MODULE__{
      config: config,
      job_queue: job_queue,
      conn: conn,
      errors: 0
    }

    fetch_and_enqueue(state)
  end

  defp fetch_and_enqueue(state) do
    state
    |> fetch
    |> enqueue(state)
    |> fetch_and_enqueue
  end

  defp fetch(state) do
    conn = state.conn
    queues = state.config.queues

    case Faktory.Protocol.fetch(conn, queues) do
      {:error, reason} ->
        log_and_sleep(state, reason)
        state = %{state | errors: state.errors + 1}
        fetch(state) # Try again.
      nil -> nil
      job -> job
    end
  end

  def enqueue(job, state) do
    if job, do: BlockingQueue.push(state.job_queue, job)
    %{state | errors: 0}
  end

  defp log_and_sleep(state, :closed) do
    log_and_sleep(state, "connection closed")
  end

  defp log_and_sleep(state, reason) do
    reason = normalize(reason)
    sleep_time = Faktory.Utils.exp_backoff(state.errors)
    Faktory.Logger.warn("fetch failed: #{reason} -- retrying in #{sleep_time/1000}s")
    Process.sleep(sleep_time)
  end

  defp normalize(reason) when is_binary(reason), do: reason
  defp normalize(reason), do: inspect(reason)

end
