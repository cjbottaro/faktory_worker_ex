defmodule BasicTest do
  use ExUnit.Case

  test "enqueing and processing a job" do
    AddWorker.perform_async([PidMap.register, 1, 2])

    receive do
      :done -> nil
    end

    assert Stack.items == [3]
  end
end
