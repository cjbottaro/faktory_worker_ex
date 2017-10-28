defmodule WorkerConfig do
  use Faktory.Configuration, :worker

  port 7421
  pool 5
end
