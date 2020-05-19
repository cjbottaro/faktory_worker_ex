defmodule Dev.RandJob do
  use Faktory.Job

  def perform do
    (:rand.uniform_real() * 1000)
    |> round()
    |> Process.sleep()
  end
end
