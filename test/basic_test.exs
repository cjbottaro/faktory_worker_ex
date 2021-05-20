defmodule BasicTest do
  use ExUnit.Case, async: false

  setup do
    :ok = Test.Client.flush()

    self = self()
    :ok = :telemetry.attach_many(
      inspect(__MODULE__),
      [
        [:faktory, :job, :start],
        [:faktory, :job, :ack],
        [:faktory, :job, :fail],
      ],
      fn subject, _time, meta, _config ->
        send(self, {subject, meta})
      end,
      %{}
    )

    on_exit(fn -> :telemetry.detach(inspect(__MODULE__)) end)

    :ok
  end

  test "enqueing and processing a job" do
    AddJob.perform_async([1, 2])

    assert_receive {
      [:faktory, :job, :ack],
      %{value: 3}
    }
  end

  test "client middleware" do
    AddJob.perform_async([1, 2], middleware: Middleware.BadMath)

    assert_receive {
      [:faktory, :job, :start],
      %{job: %{args: [2, 3]}}
    }

    assert_receive {
      [:faktory, :job, :ack],
      %{value: 5}
    }
  end

  test "worker middleware" do
    AddJob.perform_async([1, 2], queue: "middleware")

    assert_receive {
      [:faktory, :job, :start],
      %{job: %{args: [3, 4]}}
    }

    assert_receive {
      [:faktory, :job, :ack],
      %{value: 7}
    }
  end

  test "worker handles exceptions in job" do
    AddJob.perform_async([1, "foo"])

    assert_receive {
      [:faktory, :job, :fail],
      %{reason: reason}
    }

    {errtype, _, _} = Faktory.Error.down_reason_to_fail_args(reason)
    assert errtype == "ArithmeticError"
  end

  test "worker handles job dying from brutal kill" do
    DieJob.perform_async([:kill])

    assert_receive {
      [:faktory, :job, :fail],
      %{reason: reason}
    }

    {errtype, message, _} = Faktory.Error.down_reason_to_fail_args(reason)

    assert errtype == "Faktory.Error.ProcessExit"
    assert message == "killed"
  end

  test "worker handles exception from linked process" do
    DieJob.perform_async([:spawn_exception])

    assert_receive {
      [:faktory, :job, :fail],
      %{reason: reason}
    }

    {errtype, _, _} = Faktory.Error.down_reason_to_fail_args(reason)

    assert errtype == "UndefinedFunctionError"
  end

  test "worker handles brutal kill from linked process" do
    DieJob.perform_async([:spawn_kill])

    assert_receive {
      [:faktory, :job, :fail],
      %{reason: reason}
    }

    {errtype, message, _} = Faktory.Error.down_reason_to_fail_args(reason)

    assert errtype == "Faktory.Error.ProcessExit"
    assert message == "killed"
  end

end
