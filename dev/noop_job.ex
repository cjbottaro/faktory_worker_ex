defmodule Dev.NoopJob do
  @moduledoc false
  use Faktory.Job, jobtype: "Foo"
  def perform, do: nil
end
