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

  alias Faktory.{Protocol, Utils}

  @doc false
  def start_workers? do
    !!get_env(:start_workers)
  end

  @doc false
  def worker_config_module do
    get_env(:worker_config)
  end

  @doc false
  def client_config_module do
    get_env(:client_config)
  end

  @doc """
  Lower level enqueing function.

  `perform_async` delgates to this. `module` can be either an atom or string.
  A connection is checked out from the _client_ pool.

  Ex:
  ```elixir
    push(MyFunWork, [queue: "somewhere"], [1, 2])
    push("BoringWork", [retries: 0, backtrace: 10], [])
  ```
  """
  @spec push(atom | binary, Keyword.t, [term]) :: jid
  def push(module, options, args) do
    jobtype = Utils.normalize_jobtype(module)
    job = options
      |> Keyword.merge(jobtype: jobtype, args: args)
      |> Utils.stringify_keys
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
    :poolboy.transaction(client_config_module(), func)
  end

end
