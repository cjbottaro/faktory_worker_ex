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

    faktory_options queue: "default", retry: 25, backtrace: 0

    # ...
  end
  ```

  ### Runtime overrides

  You can override `faktory_options` when enqueuing a job.

  ```elixir
  MyFunkyJob.perform_async([1, "foo"], queue: "not_default")
  MyFunkyJob.perform_async([2, "bar"], retry: 0)
  ```
  """

  defmacro __using__(_options) do
    quote do
      import Faktory.Job, only: [faktory_options: 1]
      @faktory_options [queue: "default", retry: 25, backtrace: 0, middleware: []]
      @before_compile Faktory.Job

      def perform_async(args, options \\ []) do
        Faktory.push(__MODULE__, args, options)
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
    * `:retry` - How many times to retry. Default `25`
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
