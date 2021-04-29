defmodule Faktory.Logger.Command do
  @defaults [
    enable: false
  ]

  @moduledoc """
  Command logging.

  Logging for commands sent to the Faktory server.

  ## Defaults

  ```
  #{inspect @defaults, pretty: true, width: 0}
  ```

  ## Configuration

  ```
  config :faktory_worker_ex, #{inspect __MODULE__}, enable: true
  ```

  ## Telemetry

  This logger subscribes to following telemetry events.

  * `[:faktory, :command, :info]`
  * `[:faktory, :command, :push]`
  * `[:faktory, :command, :fetch]`
  * `[:faktory, :command, :ack]`
  * `[:faktory, :command, :fail]`
  * `[:faktory, :command, :flush]`
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
        [:faktory, :command, :info],
        [:faktory, :command, :push],
        [:faktory, :command, :fetch],
        [:faktory, :command, :ack],
        [:faktory, :command, :fail],
        [:faktory, :command, :flush],
      ],
      &__MODULE__.log/4,
      Map.new(config)
    )
  end

  @doc false

  def log([:faktory, :client, call], %{usec: usec}, meta, %{enable: true}) do
    time = Faktory.Utils.format_duration(usec)
    case meta.result do
      {:error, reason} ->
        Logger.warn("#{call} failure (#{inspect reason}) in #{time}")
      _success ->
        Logger.debug("#{call} success in #{time}")
    end
  end

  def log(_, _, _, _), do: nil

end
