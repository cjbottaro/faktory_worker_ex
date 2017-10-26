defmodule Faktory.Configuration do

  defmacro __using__(type) do
    quote bind_quoted: [type: type] do
      import Faktory.Configuration, only: [merge: 2, host: 1, port: 1]

      # Common defaults
      @config [host: "localhost", port: 7419]
      @config_type type # @type is special, can't use it.

      case type do
        :client ->
          @config merge(@config, pool: 10)
          import Faktory.Configuration, only: [pool: 1]
        :worker ->
          @config merge(@config, concurrency: 20, queues: ["default"])
          import Faktory.Configuration, only: [concurrency: 1, queues: 1]
      end

      def dynamic(config), do: config
      defoverridable [dynamic: 1]

      @before_compile Faktory.Configuration
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def all do
        import Faktory.Configuration, only: [new_wid: 0]
        config = @config
          |> dynamic
          |> Keyword.put_new(:wid, new_wid())
          |> Enum.map(fn {k, v} -> {k |> to_string |> String.to_atom, v} end)
          |> Map.new
      end
    end
  end

  defmacro host(host) do
    quote do
      @config merge(@config, host: unquote(host))
    end
  end

  defmacro port(port) do
    quote do
      @config merge(@config, port: unquote(port))
    end
  end

  defmacro pool(pool) do
    quote do
      @config merge(@config, pool: unquote(pool))
    end
  end

  defmacro concurrency(concurrency) do
    quote do
      @config merge(@config, concurrency: unquote(concurrency))
    end
  end

  defmacro queues(queues) do
    quote do
      @config merge(@config, queues: unquote(queues))
    end
  end

  def merge(old, new) do
    Keyword.merge(old, new)
  end

  def new_wid do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

end
