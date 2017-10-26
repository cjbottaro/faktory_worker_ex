defmodule Faktory.Job do
  defmacro __using__(_options) do
    quote do
      import Faktory.Job, only: [faktory_options: 1]
      @faktory_options [queue: "default", retries: 25, backtrace: 0]
      @before_compile Faktory.Job

      def perform_async(args) do
        perform_async(faktory_options(), args)
      end

      def perform_async(options, args) do
        Faktory.push(__MODULE__, options, args)
      end

      def set(options) do
        Keyword.merge(faktory_options(), options)
      end

      def set(options, new_options) do
        Keyword.merge(options, new_options)
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def faktory_options do
        @faktory_options
      end
    end
  end

  defmacro faktory_options(options \\ []) do
    quote do
      options = unquote(options)
      @faktory_options Keyword.merge(@faktory_options, options)
    end
  end

end
