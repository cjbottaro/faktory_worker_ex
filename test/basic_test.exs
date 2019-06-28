defmodule BasicTest do
  use ExUnit.Case, async: false

  test "enqueing and processing a job" do
    job = AddWorker.perform_async([PidMap.register, 1, 2])
    jid = job["jid"]

    assert_receive %{jid: ^jid, error: nil}
    assert_receive {:add_result, 3}
  end

  test "client middleware" do
    AddWorker.perform_async([PidMap.register, 1, 2], middleware: [BadMath])

    assert_receive {:add_result, 5}
  end

  test "worker middleware" do
    AddWorker.perform_async([PidMap.register, 1, 2], queue: "middleware")

    assert_receive {:add_result, 5}
  end

  test "worker handles exceptions" do
    job = AddWorker.perform_async([PidMap.register, 1, "foo"])
    jid = job["jid"]

    assert_receive %{jid: ^jid, error: error}
    assert error.errtype == "ArithmeticError"
  end

  test "worker handles executor dying from brutal kill" do
    job = DieWorker.perform_async([:kill])
    jid = job["jid"]

    assert_receive %{jid: ^jid, error: error}
    assert error.errtype == "exit"
    assert error.message == ":killed"
  end

  test "worker handles executor dying from linked process" do
    job = DieWorker.perform_async([:spawn])
    jid = job["jid"]

    assert_receive %{jid: ^jid, error: error}
    assert error.errtype == "UndefinedFunctionError"
  end

end
