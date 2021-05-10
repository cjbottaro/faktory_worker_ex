defmodule Faktory.Worker do
  @moduledoc """
  Create and configure a worker for _processing_ jobs.

  It works exactly the same as configuring an Ecto Repo.

  ```elixir
  defmodule MyFaktoryWorker do
    use Faktory.Worker, otp_app: :my_app
  end

  # It must be added to your app's supervision tree
  defmodule MyApp.Application do
    use Application

    def start(_type, _args) do
      children = [MyFaktoryWorker]
      Supervisor.start_link(children, strategy: :one_for_one)
    end
  end
  ```

  ## Defaults

  See `defaults/0` for default worker configuration.

  ## Compile time config

  Done with Mix.Config, duh.

  ```elixir
  use Mix.Config

  config :my_app, MyFaktoryWorker,
    host: "foo.bar",
    concurrency: 15
    queues: ["default", "other_queue"]
  ```

  ## Runtime config

  Can be done with the `c:init/1` callback.

  Can be done with environment variable tuples:
  ```elixir
  use Mix.Config

  config :my_app, MyFaktoryWorker,
    host: {:system, "FAKTORY_HOST"} # No default, errors if FAKTORY_HOST doesn't exist
    port: {:system, "FAKTORY_PORT", 1001} # Use 1001 if FAKTORY_PORT doesn't exist
  ```

  ## Shutdown grace period

  The `:shutdown_grace_period` config option specifies how long to wait for any currently
  running jobs to finish after receiving instruction to shutdown. For example from
  receiving a SIGTERM, or from the Faktory server issuing a `terminate` command
  (clicking the stop button in the web UI).
  """

  @defaults [
    host: "localhost",
    port: 7419,
    middleware: [],
    concurrency: 20,
    queues: ["default"],
    password: nil,
    use_tls: false,
    reporter_count: 1,
    shutdown_grace_period: 25_000
  ]

  @doc """
  Return the default worker configuration.

  ```elixir
  iex(1)> Faktory.Worker.defaults
  [
    host: "localhost",
    port: 7419,
    middleware: [],
    concurrency: 20,
    queues: ["default"],
    password: nil,
    use_tls: false,
    reporter_count: 1,
    shutdown_grace_period: 25_000,
  ]
  ```
  """
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

    end
  end

  @doc """
  Callback for doing runtime configuration.

  ```
  defmodule MyFaktoryWorker do
    use Faktory.Worker, otp_app: :my_app

    def init(config) do
      config
      |> Keyword.put(:host, "foo.bar")
      |> Keyword.merge(queues: ["default", "other_queue"], concurrency: 10)
    end
  end
  ```
  """
  @callback init(config :: Keyword.t) :: Keyword.t

  @doc """
  Returns a worker's config after all runtime modifications have occurred.

  ```elixir
  iex(1)> MyFaktoryWorker.config
  [
    wid: "a2ba187ec640215f",
    host: "localhost",
    port: 7419,
    middleware: [],
    concurrency: 20,
    queues: ["default"],
    password: nil,
    use_tls: false,
    reporter_count: 1,
    shutdown_grace_period: 25_000,
  ]
  ```

  Don't mess with the `wid`. 🤨
  """
  @callback config :: Keyword.t

  @doc false
  def config(module) do
    Faktory.Configuration.call(module, @defaults)
  end

  def child_spec(module, _options) do
    %{
      id: module,
      start: {Faktory.Supervisor, :start_link, [module]},
      type: :supervisor
    }
  end
end
