defmodule BasicTest do
  use ExUnit.Case

  setup do
    Stack.clear
    
    :ok
  end

  test "enqueing and processing a job" do
    job = AddWorker.perform_async([PidMap.register, 1, 2])
    jid = job["jid"]

    assert_receive {:report_ack, %{job: %{"jid" => ^jid}}}
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

  test "worker handles exceptions" do
    job = AddWorker.perform_async([PidMap.register, 1, "foo"])
    jid = job["jid"]

    assert_receive {:report_fail, %{job: %{"jid" => ^jid}, error: error}}
    assert {"ArithmeticError", _, _} = error
  end

  test "worker handles {:EXIT, pid, :KILLED}" do
    job = DieWorker.perform_async([true])
    jid = job["jid"]

    assert_receive {:report_fail, %{job: %{"jid" => ^jid}, error: error}}
    assert {"killed", _, _} = error
  end

end
