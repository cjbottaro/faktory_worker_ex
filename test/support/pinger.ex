defmodule Pinger do
  use Faktory.Middleware, :worker

  def call(job, f) do
    pid_key = Enum.find_value Stack.items, fn
      {:ping_me, pid_key} -> pid_key
      _ -> nil
    end

    if pid_key do
      send(PidMap.get(pid_key), :ping)
    end

    f.(job)
  end

end
