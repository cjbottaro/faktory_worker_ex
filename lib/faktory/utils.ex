defmodule Faktory.Utils do
  @moduledoc false

  def put_unless_nil(enum, _key, nil), do: enum
  def put_unless_nil(enum, key, value) when is_list(enum) do
    Keyword.put(enum, key, value)
  end
  def put_unless_nil(enum, key, value) when is_map(enum) do
    Map.put(enum, key, value)
  end

  def default_from_key(enum, dst, src) when is_list(enum) do
    if enum[dst] do
      enum
    else
      Keyword.put(enum, dst, enum[src])
    end
  end

  def default_from_key(enum, dst, src) when is_map(enum) do
    if Map.get(enum, dst) do
      enum
    else
      Map.put(enum, dst, Map.get(enum, src))
    end
  end

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

    # Not really dry since Faktory does this same call to populate a module var,
    # but we can't call functions on Faktory otherwise we get a circular
    # dependency and deadlock errors.
    app_name = Application.get_application(Faktory)

    cond do
      function_exported?(Mix, :env, 1) -> Mix.env
      Application.get_env(app_name, :env) -> Application.get_env(app_name, :env)
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

end
