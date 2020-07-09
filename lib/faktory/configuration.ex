defmodule Faktory.Configuration do
  @moduledoc false

  def call(module, defaults) do
    config = Application.get_env(module.otp_app, module, [])

    if config[:configured] do
      Keyword.delete(config, :configured)
    else
      config =
        defaults
        |> Keyword.merge(config)
        |> module.init
        # Client connection don't have wid.
        |> put_wid(module.type)
        |> resolve_all_env_vars
        |> Keyword.put_new(:module, module)
        |> Keyword.put(:jobtype_map, jobtype_map(module.otp_app))
        |> Keyword.merge(Faktory.get_env(:cli_options) || [])
        |> normalize
        |> Keyword.put(:configured, true)

      Application.put_env(module.otp_app, module, config)
      call(module, defaults)
    end
  end

  defp jobtype_map(otp_app) do
    {:ok, modules} = :application.get_key(otp_app, :modules)

    Enum.reduce(modules, %{}, fn module, acc ->
      # Trying to call a function on a module will implicitly load it, but
      # function_exported?/1 will return false on unloaded modules, so we
      # have to make sure the module is loaded before calling it.
      {:module, ^module} = Code.ensure_loaded(module)
      
      behaviours =
        cond do
          Kernel.function_exported?(module, :__info__, 1) ->
            module.__info__(:attributes)[:behaviour] || []

          Kernel.function_exported?(module, :module_info, 1) ->
            module.module_info(:attributes)[:behaviour] || []

          true ->
            []
        end

      if Faktory.Job in behaviours do
        Map.put(acc, module.faktory_options[:jobtype], module)
      else
        acc
      end
    end)
  end

  defp put_wid(config, :worker), do: Keyword.put(config, :wid, Faktory.Utils.new_wid())
  defp put_wid(config, :client), do: config

  defp resolve_all_env_vars(config) do
    Enum.map(config, fn {k, v} ->
      v =
        case v do
          {:system, name, default} -> resolve_env_var(name, default)
          {:system, name} -> resolve_env_var(name)
          v -> v
        end

      {k, v}
    end)
  end

  defp resolve_env_var(name, default \\ nil) do
    name |> to_string |> System.get_env() || default
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
