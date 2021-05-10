defmodule Faktory.Logger do
  @moduledoc false
  require Logger

  def debug(msg), do: log(:debug, "[faktory] #{msg}")
  def info(msg),  do: log(:info,  "[faktory] #{msg}")
  def warn(msg),  do: log(:warn,  "[faktory] #{msg}")
  def error(msg), do: log(:error, "[faktory] #{msg}")

  def log(level, message) do
    faktory_level = Faktory.get_env(:log_level, :debug)
    if Logger.compare_levels(faktory_level, level) != :gt do
      Logger.log(level, message)
    end
  end

end
