defmodule Faktory.Logger.Job do
  @defaults [
    enable: true
  ]

  @moduledoc """
  Job logging.

  Logging regarding the lifecycle of a job.

  ## Defaults

  ```
  #{inspect @defaults, pretty: true, width: 0}
  ```

  ## Configuration

  ```
  config :faktory_worker_ex, #{inspect __MODULE__}, enable: false
  ```

  ## Telemetry

  This logger subscribes to following telemetry events.

  * `[:faktory, :job, :start]`
  * `[:faktory, :job, :ack]`
  * `[:faktory, :job, :fail]`
  * `[:faktory, :job, :timeout]`
  """

  require Logger

  @doc false
  def init do
    config = Application.get_application(__MODULE__)
    |> Application.get_env(__MODULE__, [])

    config = Keyword.merge(@defaults, config)

    :telemetry.attach_many(
      inspect(__MODULE__),
      [
        [:faktory, :job, :start],
        [:faktory, :job, :ack],
        [:faktory, :job, :fail],
        [:faktory, :job, :timeout],
      ],
      &__MODULE__.log/4,
      Map.new(config)
    )
  end

  @doc false

  def log([:faktory, :job, :start], _time, meta, %{enable: true}) do
    %{job: job, worker: worker} = meta
    %{jid: jid, jobtype: jobtype, args: args} = job
    args = inspect(args, binaries: :as_strings, charlists: :as_lists)
    name = Faktory.Worker.human_name(worker)
    Logger.info "🚀 #{name} started jid-#{jid} (#{jobtype}) #{args}"
  end

  def log([:faktory, :job, :ack], %{usec: usec}, meta, %{enable: true}) do
    %{job: job, worker: worker} = meta
    %{jid: jid, jobtype: jobtype} = job
    time = Faktory.Utils.format_duration(usec)
    name = Faktory.Worker.human_name(worker)
    Logger.info "🥂 #{name} acked jid-#{jid} (#{jobtype}) in #{time}"
  end

  def log([:faktory, :job, :fail], %{usec: usec}, meta, %{enable: true}) do
    %{job: job, worker: worker} = meta
    %{jid: jid, jobtype: jobtype} = job
    time = Faktory.Utils.format_duration(usec)
    name = Faktory.Worker.human_name(worker)
    Logger.info "💥 #{name} failed jid-#{jid} (#{jobtype}) in #{time}"
  end

  def log([:faktory, :job, :timeout], %{usec: usec}, meta, %{enable: true}) do
    %{job: job, worker: worker} = meta
    %{jid: jid, jobtype: jobtype} = job
    time = Faktory.Utils.format_duration(usec)
    name = Faktory.Worker.human_name(worker)
    Logger.info "⏱  #{name} timed out jid-#{jid} (#{jobtype}) in #{time}"
  end

  def log(_, _, _, _), do: nil

end
