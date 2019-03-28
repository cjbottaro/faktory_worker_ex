defmodule Faktory.Utils do
  @moduledoc false

  # Retain this at compile time since Mix.* will not be available in release builds
  @app_name Mix.Project.config[:app]

  def app_name, do: @app_name

  def module_name(string) when is_binary(string) do
    String.replace_prefix(string, "Elixir.", "")
  end

  def module_name(module) when is_atom(module) do
    module |> Module.split |> Enum.join(".")
  end

  # This will convert an enum into a map with string keys.
  def stringify_keys(map) do
    Enum.reduce map, %{}, fn {k, v}, acc ->
      Map.put(acc, to_string(k), v)
    end
  end

  # This will convert an enum into a map with atom keys.
  def atomify_keys(enum) do
    Enum.reduce enum, %{}, fn {k, v}, acc ->
      k = k |> to_string |> String.to_atom
      Map.put(acc, k, v)
    end
  end

  def new_wid do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  def new_jid do
    :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
  end

  def stringify(thing) do
    try do
      to_string(thing)
    rescue
      Protocol.UndefinedError -> inspect(thing)
    end
  end

  def now_in_ms do
    :os.system_time(:milli_seconds)
  end

  def env do
    cond do
      function_exported?(Mix, :env, 1) -> Mix.env
      Application.get_env(@app_name, :env) -> Application.get_env(@app_name, :env)
      Map.has_key?(System.get_env, "MIX_ENV") -> System.get_env("MIX_ENV")
      true -> :dev
    end
  end

  def hash_password(iterations, password, salt) do
    1..iterations
    |> Enum.reduce(password <> salt, fn(_i, acc) ->
      :crypto.hash(:sha256, acc)
    end)
    |> Base.encode16()
    |> String.downcase()
  end

  defmacro if_test(do: block) do
    if Faktory.Utils.env == :test do
      quote do: unquote(block)
    end
  end

  def unix_pid do
    System.get_pid |> String.to_integer
  end

  def hostname do
    {:ok, hostname} = :inet.gethostname
    to_string(hostname)
  end

  def exp_backoff(count) do
    time = (:math.pow(1.4, count) + :rand.uniform) * 1000 |> round
    if time > 32_000 do
      32_000 + (:rand.uniform * 1000 |> round)
    else
      time
    end
  end

end
