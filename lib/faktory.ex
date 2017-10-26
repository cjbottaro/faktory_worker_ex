defmodule Faktory do
  @moduledoc """
  Documentation for Faktory.
  """

  # This should match what's in mix.exs. I couldn't figure out how to just
  # use what's in mix.exs. That would be nice.
  @app_name :faktory_worker_ex

  alias Faktory.{Protocol, Utils}

  def start_workers? do
    !!get_env(:start_workers)
  end

  def worker_config_module do
    get_env(:worker_config)
  end

  def client_config_module do
    get_env(:client_config)
  end

  def push(module, options, args) do
    jobtype = Utils.normalize_jobtype(module)
    job = options
      |> Keyword.merge(jobtype: jobtype, args: args)
      |> Utils.stringify_keys
    with_conn(&Protocol.push(&1, job))
  end

  def info do
    with_conn(&Protocol.info(&1))
  end

  def get_env(key) do
     Application.get_env(@app_name, key)
  end

  def put_env(key, value) do
    Application.put_env(@app_name, key, value)
  end

  def with_conn(func) do
    :poolboy.transaction(client_config_module(), func)
  end

end
