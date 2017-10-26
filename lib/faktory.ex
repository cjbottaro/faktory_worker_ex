defmodule Faktory do
  @moduledoc """
  Documentation for Faktory.
  """

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

  def get_env(key) do
     Application.get_env(:faktory_worker_ex, key)
  end

  def put_env(key, value) do
    Application.put_env(:faktory_worker_ex, key, value)
  end

  defp with_conn(func) do
    :poolboy.transaction(client_config_module(), func)
  end

end
