defmodule Faktory.Configuration.Worker do
  @moduledoc false

  @defaults [
    host: "localhost", port: 7419, middleware: [], concurrency: 20, wid: nil,
    queues: ["default"], password: nil, use_tls: false
  ]

  def defaults, do: @defaults

  defmacro __using__(_options) do
    quote do

      def config do
        alias Faktory.Configuration
        Configuration.Worker.config(__MODULE__, Configuration.Worker.defaults)
      end

      def init(config), do: config
      defoverridable [init: 1]

      def type, do: :worker
      def client?, do: type() == :client
      def worker?, do: type() == :worker

    end
  end

  def config(module, defaults) do
    config = Faktory.Configuration.config(module, defaults)
    Map.put_new(config, :pool, config.concurrency)
  end

end
