defmodule Dev.Pool do
  @moduledoc false

  use ConnectionPool, size: 2

  def start_spec(name) do
    {
      Faktory.Client,
      :start_link,
      [
        [],
        [name: name]
      ]
    }
  end
end
