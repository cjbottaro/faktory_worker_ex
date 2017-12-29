defmodule Faktory.Configuration.Client do
  @moduledoc false

  defstruct [
    host: "localhost", port: 7419, pool: 10, middleware: [], fn: nil,
    name: "default", wid: nil, password: nil
  ]

end
