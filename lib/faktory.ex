defmodule Faktory do
  @moduledoc """
  Some utility functions and such. See README for general usage.
  """

  # Represents a unique job id.
  @type jid :: binary

  # A Faktory job.
  @type job :: map

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

  `perform_async` delgates to this. `module` can be either an atom or string.
  A connection is checked out from the _client_ pool.

  Ex:
  ```elixir
    push(MyFunWork, [queue: "somewhere"], [1, 2])
    push("BoringWork", [retry: 0, backtrace: 10], [])
  ```
  """
  @spec push(atom | binary, Keyword.t, [term]) :: job
  def push(module, args, options \\ []) do
    import Faktory.Utils, only: [new_jid: 0, if_test: 1]
    alias Faktory.Middleware

    module = Module.safe_concat([module])
    options = Keyword.merge(module.faktory_options, options)
    client = options[:client] || get_env(:default_client)
    jobtype = options[:jobtype]

    job = options
      |> Keyword.merge(jid: new_jid(), jobtype: jobtype, args: args)
      |> Utils.stringify_keys

    # This is weird, middleware is configured in the client config module,
    # but we allow overriding in faktory_options and thus push options.
    middleware = case options[:middleware] do
      nil -> client.config[:middleware]
      [] -> client.config[:middleware]
      middleware -> middleware
    end

    # To facilitate testing, we keep a map of jid -> pid and send messages to
    # the pid at various points in the job's lifecycle.
    if_test do: TestJidPidMap.register(job["jid"])

    Middleware.traverse(job, middleware, fn job ->
      with_conn(options, &Protocol.push(&1, job))
    end)

    %{ "jid" => jid, "args" => args } = job
    Logger.info "Q 🕒 #{inspect self()} jid-#{jid} (#{jobtype}) #{inspect(args)}"

    job
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
