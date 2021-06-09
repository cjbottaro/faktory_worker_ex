defmodule ErrorTest do
  use ExUnit.Case, async: true

  test "timeout error" do
    reason = {:timeout, {Task.Supervised, :stream, [5000]}}
    {e, []} = Faktory.Error.down_reason_to_exception(reason)
    %Faktory.Error.ProcessExit{} = e
  end

end
