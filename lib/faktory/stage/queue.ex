defmodule Faktory.Stage.Queue do
  @moduledoc false

  def child_spec(config) do
    %{
      id: {config.module, __MODULE__},
      start: {__MODULE__, :start_link, [config]},
    }
  end

  def name(config) do
    Faktory.Registry.name({config.module, __MODULE__})
  end

  def start_link(config) do
    GenStage.start_link(__MODULE__, config, name: name(config))
  end

  def init(config) do
    Faktory.Logger.debug "Queue stage #{inspect self()} starting up"
    {:producer_consumer, config, subscribe_to: subscribe_to(config)}
  end

  def handle_events([job], _from, state) do
    {:noreply, [job], state}
  end

  defp subscribe_to(config) do
    Enum.map Faktory.Stage.Fetcher.names(config), fn fetcher ->
      {fetcher, max_demand: 1, min_demand: 0}
    end
  end

end
