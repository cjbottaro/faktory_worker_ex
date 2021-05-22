defmodule Faktory.Middleware do
  @moduledoc ~S"""
  Middleware behaviour for client (enqueing) and worker (dequeing/processing).

  On the client side, a middleware chain alters a job before it is enqueued.

  On the worker side, a middleware chain alters a job before it is processed.

  It's just a simple behaviour that requires `call/2`. Almost no reason to
  even make it a behaviour other than having a module to attach documentation to.

  ```elixir
  defmodule FooMiddleware do
    use Faktory.Middleware

    def call(job, f) do
      # Alter a job
      job = %{job | queue: "new-queue"}

      # Pass it along down the chain.
      job = f.(job)

      # Something could have altered it down stream.
      job[:queue] == "new-new-queue"

      # Always return the job for other middlewares further up the chain.
      job
    end
  end
  ```

  Next add it to the worker configuration.

  ```elixir
  config :my_cool_app, MyWorker,
    middleware: [FooMiddleware]
  ```

  It is important to capture the changes to the job after passing it along:
  ```elixir
  job = f.(job)
  ```
  That way you can see any changes made after handing it off and it comes
  up down the chain after being processed.

  ## Global configuration

  Set middleware for all workers.
  ```
  config :faktory_worker_ex, Faktory.Worker,
    middleware: [FooMiddleware, BarMiddleware]
  ```

  Set middleware for all jobs. This will affect all `c:Faktory.Job.perform_async/2` calls.
  ```
  config :faktory_worker_ex, Faktory.Job,
    middleware: [FooMiddleware, BarMiddleware]
  ```

  Set middelware for all `Faktory.Client.push/3`, `c:Faktory.Client.push/2`,
  and `c:Faktory.Job.perform_async/2` calls.
  ```
  config :faktory_worker_ex, Faktory.Client,
    middleware: [FooMiddleware, BarMiddleware]
  ```
  """

  defmacro __using__(_options) do
    quote do
      @behaviour Faktory.Middleware
    end
  end

  @type job :: Faktory.push_job()

  @doc """
  Invoke the middleware.

  The function invokes the next middleware in the chain. You can modify the job
  both before and after invoking the function. The function may return a
  modified job. `call/2` must return a job.

  Example middleware that does nothing:
  ```elixir
    def call(job, f) do
      f.(job)
    end
  ```
  """
  @callback call(job, (job -> job)) :: job

  @doc false
  # This hurts my brain.
  def traverse(job, chain, done_fn) do
    chain = List.wrap(chain)

    walker = fn
      job, [], _next ->
        done_fn.(job)
      job, [middleware | chain], next ->
        monad = fn job -> next.(job, chain, next) end
        middleware.call(job, monad)
    end

    walker.(job, chain, walker)
  end

end
