use Mix.Config

config :faktory_worker_ex, :test, true

config :faktory_worker_ex, Test.Client,
  port: 7421,
  pool: 5

config :faktory_worker_ex, Test.DefaultWorker,
  port: 7421,
  concurrency: 2

config :faktory_worker_ex, Test.MiddlewareWorker,
  port: 7421,
  concurrency: 2,
  middleware: [BadMath],
  queues: ["middleware"]
