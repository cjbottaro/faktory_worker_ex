defmodule Faktory.Logger.Connection do
  @defaults [
    enable: true
  ]

  @moduledoc """
  Connection logging.

  Logging regarding the state of connections.

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

  * `[:faktory, :connection, :success]`
  * `[:faktory, :connection, :failure]`
  * `[:faktory, :connection, :disconnect]`
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
        [:faktory, :connection, :success],
        [:faktory, :connection, :failure],
        [:faktory, :connection, :disconnect],
      ],
      &__MODULE__.log/4,
      Map.new(config)
    )
  end

  @doc false

  def log([:faktory, :connection, :success], %{usec: usec}, meta, %{enable: true}) do
    time = Faktory.Utils.format_duration(usec)
    server = "#{meta.config.host}:#{meta.config.port}"

    if meta.disconnected do
      Logger.info("Connection reestablished to #{server} in #{time}")
    else
      Logger.debug("Connection established to #{server} in #{time}")
    end
  end

  def log([:faktory, :connection, :failure], %{usec: usec}, meta, %{enable: true}) do
    time = Faktory.Utils.format_duration(usec)
    server = "#{meta.config.host}:#{meta.config.port}"

    Logger.warn("Connection failed to #{server} (#{meta.reason}), down for #{time}")
  end

  def log([:faktory, :connection, :disconnect], _time, meta, %{enable: true}) do
    server = "#{meta.config.host}:#{meta.config.port}"

    Logger.warn("Disconnected from #{server} (#{meta.reason})")
  end

  def log(_, _, _, _), do: nil

end
