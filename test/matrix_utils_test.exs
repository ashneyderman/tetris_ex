defmodule MatrixUtilsTest do
  use ExUnit.Case

  describe "apply_each_cell/2" do
    test "simple application" do
      assert [[4, 4], [4, 4]] ==
               MatrixUtils.apply_each_cell(Matrix.new(2, 2, 2), fn x -> x * 2 end)
    end
  end
end
