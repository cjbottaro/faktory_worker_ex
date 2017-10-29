defmodule Faktory.Logger do
  @moduledoc false
  require Logger

  defmacro __using__(_) do
    quote do
      import Faktory.Logger
    end
  end

  def debug(msg), do: log(:debug,"[faktory] #{msg}")
  def info(msg), do: log(:info, "[faktory] #{msg}")
  def warn(msg), do: log(:warn, "[faktory] #{msg}")
  def error(msg), do: log(:error, "[faktory] #{msg}")

  defp log(level, msg) do
    if level_high_enough?(level) do
      Logger.log(level, msg)
    end
  end

  @level_map [debug: 0, info: 1, warn: 2, error: 3]

  defp level_high_enough?(level) do
    level = @level_map[level]
    config_level = @level_map[Faktory.log_level]

    level >= config_level
  end

end
