defmodule ErrorTest do
  use ExUnit.Case, async: true

  test "timeout error" do
    reason = {:timeout, {Task.Supervised, :stream, [5000]}}
    {errtype, errmsg, []} = Faktory.Error.down_reason_to_fail_args(reason)
    assert errtype == "ErlangError"
    assert String.contains?(errmsg, "timeout")
  end

end
