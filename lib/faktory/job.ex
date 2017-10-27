defmodule Faktory.Job do
  @moduledoc """
  Use this module to create your job processors.

  ### Getting started

  All that is required is to define a `perform` function that takes zero or more
  arguments.

  ```elixir
  defmodule MyFunkyJob do
    use Faktory.Job

    def perform(arg1, arg2) do
      # ... do something ...
    end
  end

  # To enqueue jobs of this type.
  MyFunkyJob.perform_async([1, "foo"])
  ```

  Notice `perform_async` takes a list who's size must match exactly the airty of
  `perform`.

  ### Configuring

  You can configure various aspects of the job by passing a keyword list to
  `faktory_options/1`. All keys are optional and their default values are
  shown in the example below.

  ```elixir
  defmodule MyFunkyJob do
    use Faktory.Job

    faktory_options queue: "default", retries: 25, backtrace: 0

    # ...
  end
  ```

  ### Runtime configuration

  You can alter the aspects of a singular job at runtime in a couple of ways.

  ```elixir
  MyFunkyJob.set(queue: "not_default") |> MyFunkyJob.perform_async([1, "foo"])
  ```

  That chaining syntax as inspired by the Ruby Faktory Worker and I'm not sure
  if it's a good fit. You can just set options directly in the call to `perform_async`:

  ```elixir
  MyFunkyJob.perform_async([queue: "not_default"], [1, "foo"])
  ```
  """

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

  @doc """
  Set default options for all jobs of this type.

  ## Options

    * `:queue` - Name of queue. Default `"default"`
    * `:retries` - How many times to retry. Default `25`
    * `:backtrace` - How many lines of backtrace to store if the job errors. Default `0`
  """
  @spec faktory_options(Keyword.t) :: nil
  defmacro faktory_options(options) do
    quote do
      options = unquote(options)
      @faktory_options Keyword.merge(@faktory_options, options)
    end
  end

end
