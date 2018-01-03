defmodule BadMath do
  use Faktory.Middleware

  def call(job, chain, f, options \\ nil) do
    job = Map.update! job, "args", fn [pid, x, y | []] ->
      [pid, x+1, y+1]
    end

    if options do
      f.(job, chain, options)
    else
      f.(job, chain)
    end
  end

end
