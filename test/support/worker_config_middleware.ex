defmodule WorkerConfigMiddleware do
  use Faktory.Configuration, :worker

  port 7421
  concurrency 2
  pool 2
  queues ["middleware"]
  middleware [BadMath]
end
