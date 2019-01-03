defmodule Faktory.Configuration do
  @moduledoc false

  def call(module, defaults) do
    config = Application.get_env(module.otp_app, module, [])
    if config[:configured] do
      Keyword.delete(config, :configured)
    else
      config = defaults
      |> Keyword.merge(config)
      |> module.init
      |> put_wid(module.type) # Client connection don't have wid.
      |> resolve_all_env_vars
      |> normalize
      |> Keyword.put(:configured, true)
      Application.put_env(module.otp_app, module, config)
      call(module, defaults)
    end
  end

  defp put_wid(config, :worker), do: Keyword.put(config, :wid, Faktory.Utils.new_wid)
  defp put_wid(config, :client), do: config

  defp resolve_all_env_vars(config) do
    Enum.map(config, fn {k, v} ->
      v = case v do
        {:system, name, default} -> resolve_env_var(name, default)
        {:system, name} -> resolve_env_var(name)
        v -> v
      end
      {k, v}
    end)
  end

  defp resolve_env_var(name, default \\ nil) do
    (name |> to_string |> System.get_env) || default
  end

  def normalize(config) do
    case config[:port] do
      port when is_binary(port) ->
        port = String.to_integer(port)
        Keyword.put(config, :port, port)
      port when is_integer(port) ->
        config
    end
  end

end
