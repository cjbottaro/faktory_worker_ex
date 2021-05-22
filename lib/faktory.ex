defmodule Faktory do
  @moduledoc """
  Types shared by multiple modules.

  If you're looking for how to use this library, see the [README](README.md) or other
  module docs.
  """

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
  Job argument for `Faktory.Client.push/3` and `Faktory.Connection.push/2`.

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

end
