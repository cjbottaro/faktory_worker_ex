defmodule BasicTest do
  use ExUnit.Case

  setup do
    Stack.clear
  end

  test "enqueing and processing a job" do
    AddWorker.perform_async([PidMap.register, 1, 2])

    receive do
      {:add_result, n} -> assert n == 3
    end
  end

  test "client middleware" do
    AddWorker.perform_async(
      [middleware: [BadMath]],
      [PidMap.register, 1, 2]
    )

    receive do
      {:add_result, n} -> assert n == 5
    end
  end

  test "worker middleware" do
    pid_key = PidMap.register
    Stack.push({:ping_me, pid_key})

    AddWorker.perform_async([pid_key, 1, 2])

    receive do
      :ping -> assert(true)
    end

    receive do
      {:add_result, n} -> assert n == 3
    end
  end

end
