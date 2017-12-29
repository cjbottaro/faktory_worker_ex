defmodule Faktory do
  @moduledoc """
  Some utility functions and such. See README for general usage.
  """

  # Represents a unique job id.
  @type jid :: binary

  # A connection to the Faktory server.
  @type conn :: pid

  # This should match what's in mix.exs. I couldn't figure out how to just
  # use what's in mix.exs. That would be nice.
  @app_name :faktory_worker_ex

  alias Faktory.{Logger, Protocol, Utils, Configuration}

  defdelegate env, to: Utils

  @doc false
  def start_workers? do
    !!get_env(:start_workers)
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
  @spec push(atom | binary, Keyword.t, [term]) :: jid
  def push(module, args, options \\ []) do
    import Faktory.Utils, only: [new_jid: 0]
    import Faktory.TestHelp, only: [if_test: 1]

    module = Module.safe_concat([module])
    options = Keyword.merge(module.faktory_options, options)

    jobtype = Utils.module_name(module)
    job = options
      |> Keyword.merge(jid: new_jid(), jobtype: jobtype, args: args)
      |> Utils.stringify_keys

    # This is weird, middleware is configured in the client config module,
    # but we allow overriding in faktory_options and thus push options.
    middleware = case options[:middleware] do
      nil -> Configuration.fetch(:client).middleware
      [] -> Configuration.fetch(:client).middleware
      middleware -> middleware
    end

    # To facilitate testing, we keep a map if jid -> pid and send messages to
    # the pid at various points in the job's lifecycle.
    if_test do
      TestJidPidMap.register(job["jid"])
    end

    traverse_middleware(job, middleware)

    %{ "jid" => jid, "args" => args } = job
    Logger.debug "Q #{inspect self()} jid-#{jid} (#{jobtype}) #{inspect(args)}"

    job
  end

  defp traverse_middleware(job, []) do
    do_push(job)
    job
  end

  defp traverse_middleware(job, [middleware | chain]) do
    middleware.call(job, chain, &traverse_middleware/2)
  end

  defp do_push(job) do
    with_conn(&Protocol.push(&1, job))
  end

  @doc """
  Get info from the Faktory server.

  Returns the info as a map (parsed JSON).
  Checks out a connection from the _client_ pool.
  """
  @spec info :: map
  def info do
    with_conn(&Protocol.info(&1))
  end

  @doc """
  Flush (clear) the Faktory db.

  All job info will be lost.
  Checks out a connection from the _client_ pool.
  """
  @spec flush :: :ok | {:error, binary}
  def flush do
    with_conn(&Protocol.flush(&1))
  end

  @doc """
  Return the log level.

  The log level can be set to anything greater than or equal to Logger's level.

  ```elixir
  use Mix.Config
  config faktory_worker_ex, log_level: :info
  ```
  """
  @spec log_level :: atom
  def log_level do
    get_env(:log_level) || Application.get_env(:logger, :level)
  end

  @doc false
  def get_env(key) do
     Application.get_env(@app_name, key)
  end

  @doc false
  def put_env(key, value) do
    Application.put_env(@app_name, key, value)
  end

  @doc """
    Need a raw connection to the Faktory server?

    This checks one out, passes it to the given function, then checks it back
    in. See the (undocument) `Faktory.Protocol` module for what you can do
    with a connection.
  """
  @spec with_conn((conn -> term)) :: term
  def with_conn(func) do
    config = Configuration.fetch(:client)
    :poolboy.transaction(config.name, func)
  end

end
