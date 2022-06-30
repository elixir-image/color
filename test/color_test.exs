defmodule ColorTest do
  use ExUnit.Case
  doctest Color

  test "greets the world" do
    assert Color.hello() == :world
  end
end
