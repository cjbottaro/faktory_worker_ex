defmodule JobTest do
  use Faktory.Job

  faktory_options queue: "not_default"

  def perform(n) do
    IO.puts(n * n)
  end

end
