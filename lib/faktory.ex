defmodule Faktory do
  @moduledoc false

  # Represents a unique job id.
  @type jid :: binary

  @type json :: (
    binary  |
    integer |
    float   |
    nil     |
    [json]  |
    %{binary => json}
  )

  # A Faktory job.
  @type job :: %{
    required(binary) => json
  }

  # A connection to the Faktory server.
  @type conn :: pid

  def get_env(key, default \\ nil) do
    Application.get_env(:faktory_worker_ex, key, default)
  end

  def put_env(key, value) do
    Application.put_env(:faktory_worker_ex, key, value)
  end

  @doc false
  def start_workers? do
    !!get_env(:start_workers)
    or !!System.get_env("START_FAKTORY_WORKERS")
  end

  def default_client() do
    Application.get_env(:faktory_worker_ex, :default_client)
  end

end
