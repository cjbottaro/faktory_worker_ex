defmodule Faktory.Logger.Socket do
  @defaults [
    enable: false
  ]

  @moduledoc """
  Socket logging.

  This provides very low level logging on sockets.

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

  * `[:faktory, :socket, :send]`
  * `[:faktory, :socket, :recv]`
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
        [:faktory, :socket, :recv],
        [:faktory, :socket, :send],
      ],
      &__MODULE__.log/4,
      Map.new(config)
    )
  end

  @doc false

  def log([:faktory, :socket, :recv], time, %{result: {:ok, data}}, %{enable: true}) do
    time = Faktory.Utils.format_duration(time.usec)

    Logger.debug("<<- #{inspect data} in #{time}")
  end

  def log([:faktory, :socket, :send], time, %{result: :ok, data: data}, %{enable: true}) do
    data = case data do
      data when is_list(data) -> IO.iodata_to_binary(data)
      data -> data
    end

    time = Faktory.Utils.format_duration(time.usec)

    Logger.debug("->> #{inspect data} in #{time}")
  end

  def log(_, _, _, _), do: nil

end
