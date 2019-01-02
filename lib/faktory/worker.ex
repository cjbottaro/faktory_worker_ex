defmodule Faktory.Worker do
  @moduledoc false

  @defaults [
    host: "localhost",
    port: 7419,
    middleware: [],
    concurrency: 20,
    queues: ["default"],
    password: nil,
    use_tls: false
  ]

  def defaults, do: @defaults

  defmacro __using__(options) do
    quote do

      @otp_app unquote(options[:otp_app])
      def otp_app, do: @otp_app

      def init(config), do: config
      defoverridable [init: 1]

      def type, do: :worker
      def client?, do: false
      def worker?, do: true

      def config, do: Faktory.Worker.config(__MODULE__)
      def child_spec(options \\ []), do: Faktory.Worker.child_spec(__MODULE__, options)
      def start_link(options \\ []), do: Faktory.Worker.start_link(__MODULE__, options)

    end
  end

  def config(module) do
    Faktory.Configuration.call(module, @defaults)
  end

  def child_spec(module, options) do
    child_spec(module, options, Faktory.start_workers?)
  end

  def child_spec(module, options, false) do
    children = []
    args = [
      children,
      [strategy: :one_for_one]
    ]
    %{
      id: module,
      start: {Supervisor, :start_link, args},
      type: :supervisor
    }
  end

  def child_spec(module, options, true) do
    children = (0..module.config[:concurrency]-1)
    |> Enum.map(fn index ->
      %{
        id: {module, index},
        start: {Faktory.Processor, :start_link, [module.config]}
      }
    end)

    children = [
      %{
        id: {Faktory.Heartbeat, module},
        start: {Faktory.Heartbeat, :start_link, [module.config]}
      }
      | children
    ]

    args = [
      children,
      [strategy: :one_for_one]
    ]

    %{
      id: module,
      start: {Supervisor, :start_link, args},
      type: :supervisor
    }
  end
end
