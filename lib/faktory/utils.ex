defmodule Faktory.Utils do
  @moduledoc false

  def blank?(value) do
    (value |> to_string() |> String.trim()) == ""
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

  def elapsed(start_time) do
    (System.monotonic_time(:millisecond) - start_time) / 1000
  end

  def hash_password(password, salt, iterations) do
    1..iterations
    |> Enum.reduce(password <> salt, fn(_i, acc) ->
      :crypto.hash(:sha256, acc)
    end)
    |> Base.encode16()
    |> String.downcase()
  end

  @doc false
  def get_all_env do
    Application.get_all_env(:faktory_worker_ex)
  end

  @doc false
  def get_env(key, default \\ nil) do
     Application.get_env(:faktory_worker_ex, key, default)
  end

  @doc false
  def put_env(key, value) do
    Application.put_env(:faktory_worker_ex, key, value)
  end

  defmacro if_test(do: block) do
    if get_env(:test) do
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
