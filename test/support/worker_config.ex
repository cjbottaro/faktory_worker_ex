defmodule WorkerConfig do
  use Faktory.Configuration, :worker

  port 7421
  concurrency 2
  pool 2
end
