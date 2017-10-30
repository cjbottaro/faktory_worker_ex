use Mix.Config

config :faktory_worker_ex,
  port: 7421,
  client: [pool: 5],
  workers: [
    default: [
      concurrency: 2
    ],
    middleware: [
      concurrency: 2,
      middleware: [BadMath],
      queues: ["middleware"]
    ]
  ]
