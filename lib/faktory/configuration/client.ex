defmodule Faktory.Configuration.Client do
  @moduledoc false

  @defaults [
    host: "localhost", port: 7419, pool: 10, middleware: [], wid: nil,
    password: nil, use_tls: false
  ]

  def defaults, do: @defaults

  defmacro __using__(_options) do
    quote do

      def config do
        Faktory.get_env(__MODULE__)
      end

      def init(config), do: config
      defoverridable [init: 1]

      def type, do: :client
      def client?, do: type() == :client
      def worker?, do: type() == :worker

    end
  end

  def reconfig(config) do
    config
  end

end
