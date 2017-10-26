defmodule FaktoryTest do
  use ExUnit.Case
  doctest Faktory

  test "greets the world" do
    assert Faktory.hello() == :world
  end
end
