defmodule AddJob do
  use Faktory.Job, client: Test.Client

  def perform(x, y) do
    x + y
  end
end
