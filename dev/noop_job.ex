defmodule Dev.NoopJob do
  use Faktory.Job
  def perform, do: nil
end
