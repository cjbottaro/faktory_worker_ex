defmodule BadMath do
  use Faktory.Middleware

  def call(job, chain, f) do
    job = Map.update! job, "args", fn [pid, x, y | []] ->
      [pid, x+1, y+1]
    end

    f.(job, chain)
  end

end
