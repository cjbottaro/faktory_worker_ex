defmodule Test.DefaultWorker do
  use Faktory.Worker, otp_app: :faktory_worker_ex
end

defmodule Test.MiddlewareWorker do
  use Faktory.Worker, otp_app: :faktory_worker_ex
end
