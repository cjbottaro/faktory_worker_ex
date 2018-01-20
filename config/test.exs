use Mix.Config

config :faktory_worker_ex, Test.Client,
  adapter: Faktory.Configuration.Client,
  port: 7421,
  pool: 5

config :faktory_worker_ex, Test.DefaultWorker,
  adapter: Faktory.Configuration.Worker,
  port: 7421,
  concurrency: 2

config :faktory_worker_ex, Test.MiddlewareWorker,
  adapter: Faktory.Configuration.Worker,
  port: 7421,
  concurrency: 2,
  middleware: [BadMath],
  queues: ["middleware"]
