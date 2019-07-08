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

  **IMPORTANT**: `perform_async` takes a list who's size must match exactly the airty of
  `perform`.

  ### Configuring

  You can configure various aspects of the job by passing a keyword list to
  `use Faktory.Job` or `faktory_options/1`. They are both functionally the
  same and it's mostly an issue of style.

  ```elixir
  defmodule MyFunkyJob do
    use Faktory.Job, queue: "default", retry: 25, backtrace: 0
  end

  # These are equivalent.

  defmodule MyFunkyJob do
    use Faktory.Job
    faktory_options queue: "default", retry: 25, backtrace: 0
  end
  ```

  See `c:faktory_options/0` for available options and defaults.

  ### Runtime overrides

  You can override `faktory_options` when enqueuing a job.

  ```elixir
  MyFunkyJob.perform_async([1, "foo"], queue: "not_default")
  MyFunkyJob.perform_async([2, "bar"], retry: 0)
  ```
  """

  @defaults [
    queue: "default",
    retry: 25,
    backtrace: 0,
    middleware: []
  ]

  @doc """
  Returns the default job configuration.

  ```elixir
  iex(1)> Faktory.Job.defaults
  #{inspect @defaults}
  ```
  """
  def defaults do
    @defaults
  end

  defmacro __using__(options) do
    quote do
      @behaviour Faktory.Job
      import Faktory.Job, only: [faktory_options: 1]
      @faktory_options Keyword.merge(Faktory.Job.defaults, jobtype: inspect(__MODULE__))
      @before_compile Faktory.Job

      faktory_options(unquote(options))

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

  @type job :: map

  @doc """
  Returns the default options for a given job module.

  ```
  iex(5)> MyFunkyJob.faktory_options
  [
    queue: "default",
    jobtype: "MyFunkyJob",
    retry: 25,
    middleware: [],
    backtrace: 10
  ]
  ```
  """
  @callback faktory_options() :: options :: Keyword.t

  @doc """
  Enqueue a job.

  `options` can override any options specified by `faktory_options/1`.

  For all valid options, see `c:faktory_options/0`.

  ```
  job_args = [123, "abc"]
  MyJob.perform_async(job_args)
  MyJob.perform_async(job_args, queue: "not_default" jobtype: "Worker::MyJob")
  ```
  """
  @callback perform_async(args :: [any], options :: Keyword.t | []) :: job

  @doc """
  Set default options for all jobs of this type.

  For all valid options and their defaults, see `c:faktory_options/0`.
  """
  @spec faktory_options(Keyword.t) :: term
  defmacro faktory_options(options) do
    quote do
      options = unquote(options)
      @faktory_options Keyword.merge(@faktory_options, options)
    end
  end

end
