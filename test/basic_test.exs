defmodule BasicTest do
  use ExUnit.Case

  setup do
    Stack.clear
  end

  test "enqueing and processing a job" do
    AddWorker.perform_async([PidMap.register, 1, 2])

    assert_receive {:add_result, 3}
  end

  test "client middleware" do
    AddWorker.perform_async(
      [middleware: [BadMath]],
      [PidMap.register, 1, 2]
    )

    assert_receive {:add_result, 5}
  end

  test "worker middleware" do
    AddWorker.perform_async(
      [queue: "middleware"],
      [PidMap.register, 1, 2]
    )

    assert_receive {:add_result, 5}
  end

end
