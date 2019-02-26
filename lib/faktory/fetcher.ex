defmodule Faktory.Fetcher do
  @moduledoc false

  defstruct [:config, :conn]

  use GenStage

  def start_link(config) do
    name = Faktory.Registry.name({config.module, __MODULE__})
    GenStage.start_link(__MODULE__, config, name: name)
  end

  def init(config) do
    {:ok, conn} = Faktory.Connection.start_link(config)

    state = %__MODULE__{
      config: config,
      conn: conn
    }

    {:producer, state}
  end

  def handle_demand(1, state) do
    conn = state.conn
    queues = state.config.queues

    job = fetch(conn, queues)
    {:noreply, [job], state}
  end

  defp fetch(conn, queues, error_count \\ 0) do
    case Faktory.Protocol.fetch(conn, queues) do
      {:error, reason} ->
        log_and_sleep(reason, error_count)
        fetch(conn, queues, error_count + 1)
      nil -> fetch(conn, queues, 0)
      job -> job
    end
  end

  defp log_and_sleep(:closed, error_count) do
    log_and_sleep("connection closed", error_count)
  end

  defp log_and_sleep(reason, error_count) do
    reason = normalize(reason)
    sleep_time = Faktory.Utils.exp_backoff(error_count)
    Faktory.Logger.warn("fetch failed: #{reason} -- retrying in #{sleep_time/1000}s")
    Process.sleep(sleep_time)
  end

  defp normalize(reason) when is_binary(reason), do: reason
  defp normalize(reason), do: inspect(reason)

end
