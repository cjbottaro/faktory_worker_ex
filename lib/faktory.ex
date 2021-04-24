defmodule Faktory do

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

  @type fetch_job :: %{
    required(:jid) => binary,
    required(:jobtype) => binary,
    required(:args) => [term],
    required(:queue) => binary,
    optional(:reserve_for) => non_neg_integer(),
    optional(:at) => binary,
    optional(:retry) => non_neg_integer(),
    optional(:backtrace) => non_neg_integer(),
    optional(:created_at) => binary,
    optional(:enqueued_at) => binary,
    optional(:failure) => json,
    optional(:custom) => json
  }

  @typedoc """
  Job argument for `Faktory.Client.push/3` and `Faktory.Connection.push/3`.

  If `:jid` is not specified, it will be filled out automatically (recommended).

  If `:args` is not specified, it will default to `[]`.

  See [The Job Payload](https://github.com/contribsys/faktory/wiki/The-Job-Payload) for more info.
  """
  @type push_job :: Keyword.t | %{
    required(:jobtype) => binary,
    required(:queue) => binary,
    optional(:args) => [json],
    optional(:jid) => binary,
    optional(:reserve_for) => non_neg_integer(),
    optional(:at) => binary,
    optional(:retry) => non_neg_integer(),
    optional(:backtrace) => non_neg_integer(),
    optional(:custom) => json
  }

  # A connection to the Faktory server.
  @type conn :: GenServer.server()

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
