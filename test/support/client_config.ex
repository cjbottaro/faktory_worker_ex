defmodule ClientConfig do
  use Faktory.Configuration, :client

  port 7421
  pool 5
end
