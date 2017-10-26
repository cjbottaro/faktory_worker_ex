defmodule Faktory.Utils do

  def normalize_jobtype(string) when is_binary(string) do
    String.replace_prefix(string, "Elixir.", "")
  end

  def normalize_jobtype(module) when is_atom(module) do
    module |> Module.split |> Enum.join(".")
  end

  # This will convert an enum into a map with string keys.
  def stringify_keys(map) do
    Enum.reduce map, %{}, fn {k, v}, acc ->
      Map.put(acc, to_string(k), v)
    end
  end
  
  def new_wid do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

end
