defmodule Dev.SleepJob do
  @moduledoc false
  use Faktory.Job

  def perform do
    Stream.repeatedly(fn ->
      IO.puts "sleeping"
      Process.sleep(1000)
    end)
    |> Stream.run()
  end

  def perform(time) do
    Process.sleep(time)
    IO.puts "done sleeping (#{time})"
  end
end
