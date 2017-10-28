defmodule Faktory.Middleware do
  @moduledoc ~S"""
  Middleware behaviour for client (enqueing) and worker (dequeing/processing).

  On the client side, a middleware chain alters a job before it is enqueued.

  On the worker side, a middleware chain alters a job before it is processed.

  It's just a simple behaviour that requires `call/3`. Almost no reason to
  even make it a behaviour other than having a module to attach documentation to.

  Let's make worker middleware that logs how long jobs take to process.

  ```elixir
  defmodule JobTimer do
    use Faktory.Middleware
    import Faktory.Utils, only: [now_in_ms: 0]
    alias Faktory.Logger

    def call(job, chain, f) do
      # Alter the job by putting a start time in the custom field.
      job = job
        |> Map.put_new("custom", %{})
        |> put_in(["custom", "start_time"], now_in_ms())

      # Pass it along to get processed.
      job = f.(job, chain)

      # Calculate the elapse time.
      elapsed = now_in_ms() - job["custom"]["start_time"]
      elapsed = (elapsed / 1000) |> Float.round(3)
      jid = job["jid"]

      Logger.info("Job #{jid} took #{elapsed} seconds!")

      # Always return the job for other middlewares further up the chain.
      job
    end
  end
  ```

  Next add it to the worker configuration.

  ```elixir
  defmodule WorkerConf do
    use Faktory.Configuration, :worker

    middleware [JobTimer]
  end
  ```

  Super contrived because we don't actually need to alter the job to time it.
  It's just meant to illustrate the idea of altering a job in a way that other
  middlewares further up or down the chain can see the change.

  It is important to capture the changes to the job after passing it along:
  ```elixir
    job = f.(job, chain)
  ```
  That way you can see any changes made after handing it off and it comes
  back down the chain after being processed.
  """

  defmacro __using__(_options) do
    quote do
      @behaviour Faktory.Middleware
    end
  end

  @type job :: map

  @type chain :: [module]

  @doc """
  Invokes the middleware

  It's hard to explain. Just look at the example in the moduledoc.
  """
  @callback call(job, chain, (job, chain -> job)) :: job

end
