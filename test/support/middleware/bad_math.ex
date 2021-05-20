defmodule Middleware.BadMath do
  use Faktory.Middleware

  def call(job, f) do
    job = update_in job[:args], fn [x, y] ->
      [x+1, y+1]
    end

    f.(job)
  end

end
