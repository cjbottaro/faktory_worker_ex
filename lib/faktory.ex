defmodule Faktory do
  @moduledoc """
  Some utility functions and such. See README for general usage.
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

  # A Faktory job.
  @type job :: %{
    required(:jobtype) => binary,
    required(:args) => [term],
    optional(:queue) => binary,
    optional(:jid) => binary,
    optional(:reserve_for) => integer,
    optional(:at) => binary,
    optional(:retry) => integer,
    optional(:backtrace) => integer
  }

  # A connection to the Faktory server.
  @type conn :: pid

  alias Faktory.{Logger, Protocol, Utils}

  @doc false
  defdelegate get_all_env(), to: Utils

  @doc false
  defdelegate get_env(key, default \\ nil), to: Utils

  @doc false
  defdelegate put_env(key, value), to: Utils

  @doc false
  def start_workers? do
    !!get_env(:start_workers) or !!System.get_env("START_FAKTORY_WORKERS")
  end

  @doc """
  Lower level enqueing function.

  Manually enqueue a Faktory job. A job is defined here:
  https://github.com/contribsys/faktory/wiki/The-Job-Payload

  This function will set the JID for you, you do not have to set it yourself.

  `options` is a keyword list specifying...

  `:client` Client module to use for a Faktory server connection. If omitted, the
  default client is used.

  `:middleware` Send the job through this middleware.

  Ex:
  ```elixir
    push(%{"jobtype" => "MyFunWork", "args" => [1, 2, "three"], "queue" => "somewhere"})
    push(job, client: ClientFoo, middleware: TheJobMangler)
  ```
  """
  @spec push(job :: %{binary => json}, options :: Keyword.t) :: {:ok, job} | {:error, reason :: binary}
  def push(job, options \\ []) do
    import Faktory.Utils, only: [new_jid: 0, if_test: 1, blank?: 1]
    alias Faktory.Middleware

    if blank?(job["jobtype"]) do
      {:error, "missing required field jobtype"}
    else
      client = options[:client] || get_env(:default_client)

      middleware = if Keyword.has_key?(options, :middleware) do
        options[:middleware] || []
      else
        client.config[:middleware]
      end

      job = if blank?(job["jid"]) do
        Map.put(job, "jid", new_jid())
      else
        job
      end

      # To facilitate testing, we keep a map of jid -> pid and send messages to
      # the pid at various points in the job's lifecycle.
      if_test do: TestJidPidMap.register(job["jid"])

      result = Middleware.traverse(job, middleware, fn job ->
        with_conn(options, &Protocol.push(&1, job))
      end)

      case result do
        {:ok, _} ->
          %{ "jid" => jid, "args" => args, "jobtype" => jobtype} = job
          Logger.info "Q 🕒 #{inspect self()} jid-#{jid} (#{jobtype}) #{inspect(args)}"
          {:ok, job}

        error -> error
      end
    end

  end

  @doc """
  Get info from the Faktory server.

  Returns the info as a map (parsed JSON).
  Checks out a connection from the _client_ pool.
  """
  @spec info :: map
  def info(options \\ []) do
    with_conn(options, &Protocol.info(&1))
  end

  @doc """
  Flush (clear) the Faktory db.

  All job info will be lost.
  Checks out a connection from the _client_ pool.
  """
  @spec flush :: :ok | {:error, binary}
  def flush(options \\ []) do
    with_conn(options, &Protocol.flush(&1))
  end

  @doc """
  Need a raw connection to the Faktory server?

  This checks one out, passes it to the given function, then checks it back
  in. See the (undocument) `Faktory.Protocol` module for what you can do
  with a connection.
  """
  @spec with_conn(Keyword.t, (conn -> term)) :: term
  def with_conn(options, func) do
    client = options[:client] || get_env(:default_client)
    :poolboy.transaction(client, func)
  end

end
