defmodule Faktory.Client do
  @moduledoc """
  Create and configure a client for _enqueing_ jobs.

  It works exatly the same as configuring an Ecto Repo.

  ```elixir
  defmodule MyFaktoryClient do
    use Faktory.Client, otp_app: MyApp
  end

  # It must be added to your app's supervision tree
  defmodule MyApp.Application do
    @moduledoc false
    use Application

    def start(_type, _args) do
      children = [MyFaktoryClient]
      Supervisor.start_link(children, strategy: :one_for_one)
    end
  end
  ```

  ## Defaults

  See `defaults/0` for default client configuration.

  ## Compile time config

  Done with Mix.Config, duh.

  ```elixir
  use Mix.Config

  config :my_app, MyFaktoryClient,
    host: "foo.bar",
    port: 1000
    pool: 10
  ```

  ## Runtime config

  Can be done with the `c:init/1` callback.

  Can be done with environment variable tuples:
  ```elixir
  use Mix.Config

  config :my_app, MyFaktoryClient,
    host: {:system, "FAKTORY_HOST"} # No default, errors if FAKTORY_HOST doesn't exist
    port: {:system, "FAKTORY_PORT", 1001} # Use 1001 if FAKTORY_PORT doesn't exist
  ```

  ## Default client

  The first client to startup is the _default client_.

  For example:
  ```elixir
  MyJob.perform_async([1, 2, 3]) # Uses default client
  MyJob.perform_async([1, 2, 3], client: OtherFaktoryClient) # Uses some other client
  ```
  """

  @defaults [
    host: "localhost",
    port: 7419,
    pool: 5,
    middleware: [],
    password: nil,
    use_tls: false
  ]

  @doc """
  Return the default client configuration.

  ```elixir
  iex(3)> Faktory.Client.defaults
  [
    host: "localhost",
    port: 7419,
    pool: 5,
    middleware: [],
    password: nil,
    use_tls: false
  ]
  ```
  """
  @spec defaults :: Keyword.t
  def defaults, do: @defaults

  defmacro __using__(options) do
    quote do

      @otp_app unquote(options[:otp_app])
      def otp_app, do: @otp_app

      def init(config), do: config
      defoverridable [init: 1]

      def type, do: :client
      def client?, do: true
      def worker?, do: false

      def config, do: Faktory.Client.config(__MODULE__)
      def child_spec(_opt \\ []), do: Faktory.Client.child_spec(__MODULE__)
      def start_link(options \\ []), do: Faktory.Client.start_link(__MODULE__, options)

    end
  end

  @doc """
  Callback for doing runtime configuration.

  ```
  defmodule MyFaktoryClient do
    use Faktory.Client, otp_app: :my_app

    def init(config) do
      config
      |> Keyword.put(:host, "foo.bar")
      |> Keyword.merge(port: 1001, pool: 10)
    end
  end
  ```
  """
  @callback init(config :: Keyword.t) :: Keyword.t

  @doc """
  Returns a client's config after all runtime modifications have occurred.

  ```elixir
  iex(5)> MyFaktoryClient.config
  [
    port: 1001,
    host: "foo.bar",
    pool: 10,
    middleware: [],
    password: nil,
    use_tls: false
  ]
  ```
  """
  @callback config :: Keyword.t

  @doc false
  def config(module) do
    Faktory.Configuration.call(module, @defaults)
  end

  @doc false
  def child_spec(module) do
    config = module.config
    name = config[:name] || module

    pool_options = [
      name: {:local, name},
      worker_module: Faktory.Connection,
      size: config[:pool],
      max_overflow: 2
    ]

    # Mark the first client started as the default client.
    if !Faktory.get_env(:default_client) do
      Faktory.put_env(:default_client, module)
    end

    :poolboy.child_spec(module, pool_options, config)
  end

end
