defmodule Dev.SleepJob do
  use Faktory.Job

  def perform do
    Stream.repeatedly(fn ->
      IO.puts "sleeping"
      Process.sleep(1000)
    end)
    |> Stream.run()
  end
end
