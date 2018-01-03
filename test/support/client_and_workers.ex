defmodule Test.Client do
  use Faktory.Configuration.Client
end

defmodule Test.DefaultWorker do
  use Faktory.Configuration.Worker
end

defmodule Test.MiddlewareWorker do
  use Faktory.Configuration.Worker
end
