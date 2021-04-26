defmodule Faktory.Logger do
  @moduledoc false
  require Logger

  def init do
    :telemetry.attach_many(
      inspect(__MODULE__),
      [
        [:faktory, :socket, :recv],
        [:faktory, :socket, :send],
        [:faktory, :connection, :success],
        [:faktory, :connection, :failure],
        [:faktory, :connection, :disconnect],
        [:faktory, :client, :info],
        [:faktory, :client, :push],
        [:faktory, :client, :fetch],
        [:faktory, :client, :ack],
        [:faktory, :client, :fail],
        [:faktory, :client, :flush],
        [:faktory, :job, :start],
        [:faktory, :job, :ack],
        [:faktory, :job, :fail],
        [:faktory, :job, :timeout],
      ],
      &__MODULE__.log/4,
      nil
    )
  end

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

  def log([:faktory, :socket, :recv], time, %{result: {:ok, data}}, _config) do
    time = Faktory.Utils.format_duration(time.usec)

    Logger.debug("<<- #{inspect data} in #{time}")
  end

  def log([:faktory, :socket, :send], time, %{result: :ok, data: data}, _config) do
    data = case data do
      data when is_list(data) -> IO.iodata_to_binary(data)
      data -> data
    end

    time = Faktory.Utils.format_duration(time.usec)

    Logger.debug("->> #{inspect data} in #{time}")
  end

  def log([:faktory, :connection, :success], %{usec: usec}, meta, _config) do
    time = Faktory.Utils.format_duration(usec)
    server = "#{meta.config.host}:#{meta.config.port}"

    if meta.disconnected do
      Logger.info("Connection reestablished to #{server} in #{time}")
    else
      Logger.debug("Connection established to #{server} in #{time}")
    end
  end

  def log([:faktory, :connection, :failure], %{usec: usec}, meta, _config) do
    time = Faktory.Utils.format_duration(usec)
    server = "#{meta.config.host}:#{meta.config.port}"

    Logger.warn("Connection failed to #{server} (#{meta.reason}), down for #{time}")
  end

  def log([:faktory, :connection, :disconnect], _time, meta, _config) do
    server = "#{meta.config.host}:#{meta.config.port}"

    Logger.warn("Disconnected from #{server} (#{meta.reason})")
  end

  def log([:faktory, :call, call], %{usec: usec}, meta, _config) do
    time = Faktory.Utils.format_duration(usec)
    case meta.result do
      {:error, _reason} ->
        Logger.warn("#{call} failed in #{time}")
      _success ->
        Logger.debug("#{call} executed in #{time}")
    end
  end

  def log([:faktory, :job, :start], _time, meta, _config) do
    %{job: job, worker: worker} = meta
    %{jid: jid, jobtype: jobtype, args: args} = job
    args = inspect(args, binaries: :as_strings, charlists: :as_lists)
    name = worker_name(worker)
    Logger.info "🚀 #{name} started jid-#{jid} (#{jobtype}) #{args}"
  end

  def log([:faktory, :job, :ack], %{usec: usec}, meta, _config) do
    %{job: job, worker: worker} = meta
    %{jid: jid, jobtype: jobtype} = job
    time = Faktory.Utils.format_duration(usec)
    name = worker_name(worker)
    Logger.info "🥂 #{name} acked jid-#{jid} (#{jobtype}) in #{time}"
  end

  def log([:faktory, :job, :fail], %{usec: usec}, meta, _config) do
    %{job: job, worker: worker} = meta
    %{jid: jid, jobtype: jobtype} = job
    time = Faktory.Utils.format_duration(usec)
    name = worker_name(worker)
    Logger.info "💥 #{name} failed jid-#{jid} (#{jobtype}) in #{time}"
  end

  def log([:faktory, :job, :timeout], %{usec: usec}, meta, _config) do
    %{job: job, worker: worker} = meta
    %{jid: jid, jobtype: jobtype} = job
    time = Faktory.Utils.format_duration(usec)
    name = worker_name(worker)
    Logger.info "⏱  #{name} timed out jid-#{jid} (#{jobtype}) in #{time}"
  end

  def log(_, _, _, _), do: nil

  defp worker_name(%{name: module}) when is_atom(module), do: inspect(module)
  defp worker_name(%{wid: wid}), do: wid

end
