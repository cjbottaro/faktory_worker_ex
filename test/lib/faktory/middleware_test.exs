defmodule TestMiddlewareA do
  def call(job, f) do
    %{pid: pid, args: args} = job

    job = Map.put(job, :args, [:a | args])
    send(pid, {:before_a, job.args})

    job = f.(job)
    send(pid, {:after_a, job.args})

    args = List.delete(args, :a)
    Map.put(job, :args, args)
  end
end

defmodule TestMiddlewareB do
  def call(job, f) do
    %{pid: pid, args: args} = job

    job = Map.put(job, :args, [:b | args])
    send(pid, {:before_b, job.args})

    job = f.(job)
    send(pid, {:after_b, job.args})

    args = List.delete(args, :b)
    Map.put(job, :args, args)
  end
end

defmodule TestMiddlewareC do
  def call(job, f) do
    %{pid: pid, args: args} = job

    job = Map.put(job, :args, [:c | args])
    send(pid, {:before_c, job.args})

    job = f.(job)
    send(pid, {:after_c, job.args})

    args = List.delete(args, :c)
    Map.put(job, :args, args)
  end
end

defmodule Faktory.MiddlewareTest do
  use ExUnit.Case, async: true

  test "basically works" do
    job = %{pid: self(), args: []}
    chain = [TestMiddlewareA, TestMiddlewareB, TestMiddlewareC]

    Faktory.Middleware.traverse(job, chain, fn job ->
      assert job.args == [:c, :b, :a]
      job
    end)

    assert_receive {:before_a, [:a]}
    assert_receive {:after_a, [:a]}

    assert_receive {:before_b, [:b, :a]}
    assert_receive {:after_b, [:b, :a]}

    assert_receive {:before_c, [:c, :b, :a]}
    assert_receive {:after_c, [:c, :b, :a]}
  end

end
