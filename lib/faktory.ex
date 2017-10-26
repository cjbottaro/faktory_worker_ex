defmodule Faktory do
  @moduledoc """
  Documentation for Faktory.
  """

  alias Faktory.{Protocol, Utils}

  def push(module, options, args) do
    jobtype = Utils.normalize_jobtype(module)
    job = options
      |> Keyword.merge(jobtype: jobtype, args: args)
      |> Utils.stringify_keys
    with_conn(&Protocol.push(&1, job))
  end

  defp with_conn(func) do
    pool = Application.get_env(:faktory, :client_config)
    :poolboy.transaction(pool, func)
  end

end
