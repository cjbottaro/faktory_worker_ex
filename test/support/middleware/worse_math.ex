defmodule Middleware.WorseMath do
  use Faktory.Middleware

  def call(job, f) do
    job = update_in job[:args], fn [x, y] ->
      [x+2, y+2]
    end

    f.(job)
  end

end
