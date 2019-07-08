defmodule Faktory.Logger do
  @moduledoc false
  require Logger

  faktory_level = Faktory.get_env(:log_level, :debug)
  logger_level = Application.get_env(:logger, :level)

  if Logger.compare_levels(faktory_level, logger_level) == :gt do
    @level faktory_level
  else
    @level logger_level
  end

  def level do
    @level
  end

  # #TODO use macros to compile out stuff.

  def debug(msg), do: log(:debug, "[faktory] #{msg}")
  def info(msg),  do: log(:info,  "[faktory] #{msg}")
  def warn(msg),  do: log(:warn,  "[faktory] #{msg}")
  def error(msg), do: log(:error, "[faktory] #{msg}")

  def log(level, message) do
    if Logger.compare_levels(@level, level) != :gt do
      Logger.log(level, message)
    end
  end

end
