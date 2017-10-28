defmodule BasicTest do
  use ExUnit.Case

  setup do
    Stack.clear
  end

  test "enqueing and processing a job" do
    AddWorker.perform_async([PidMap.register, 1, 2])

    receive do
      :done -> nil
    end

    assert Stack.items == [3]
  end

  test "client middleware" do
    AddWorker.perform_async(
      [middleware: [BadMath]],
      [PidMap.register, 1, 2]
    )

    receive do
      :done -> nil
    end

    assert Stack.items == [5]
  end

end
