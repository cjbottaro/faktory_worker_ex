defmodule Faktory.Configuration.Worker do
  @moduledoc false

  defstruct [
    host: "localhost", port: 7419, pool: nil, middleware: [], fn: nil,
    name: "default", concurrency: 20, wid: nil, queues: ["default"], password: nil
  ]

end
