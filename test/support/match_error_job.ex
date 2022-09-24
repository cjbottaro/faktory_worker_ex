defmodule MatchErrorJob do
  use Faktory.Job, client: Test.Client

  def perform(value) do
    {:ok, true} = value
  end
end
