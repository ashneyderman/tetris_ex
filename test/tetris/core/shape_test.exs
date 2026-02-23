defmodule Tetris.Core.ShapeTest do
  use ExUnit.Case

  alias Tetris.Core.Shape

  # A simple L-shaped piece for testing rotations:
  #
  #   * *    (1, 1)
  #   o      (0, 1)
  #   *      (0, 0)
  #          (0,-1)
  #
  @l_shape %Shape{label: :test, coords: [[1, 1], [0, 1], [0, 0], [0, -1]]}

  # The stick shape has half-integer coords
  @stick %Shape{label: :stick, coords: [[0, 1.5], [0, 0.5], [0, -0.5], [0, -1.5]]}

  # A simple square centered at origin
  @square %Shape{label: :square, coords: [[0.5, 0.5], [0.5, -0.5], [-0.5, -0.5], [-0.5, 0.5]]}

  describe "struct" do
    test "default values" do
      shape = %Shape{}
      assert shape.label == nil
      assert shape.coords == []
    end

    test "can be created with label and coords" do
      shape = %Shape{label: :test, coords: [[0, 0], [1, 0]]}
      assert shape.label == :test
      assert shape.coords == [[0, 0], [1, 0]]
    end
  end

  describe "rotate/2 :cw" do
    test "rotates coords 90 degrees clockwise" do
      # For a point (x, y) rotated 90° CW: (x, y) -> (y, -x)
      shape = %Shape{coords: [[1, 0]]}
      rotated = Shape.rotate(shape, :cw)
      assert rotated.coords == [[0, -1]]
    end

    test "rotates L-shape clockwise" do
      rotated = Shape.rotate(@l_shape, :cw)
      # (1,1) -> (1,-1), (0,1) -> (1,0), (0,0) -> (0,0), (0,-1) -> (-1,0)
      assert rotated.coords == [[1, -1], [1, 0], [0, 0], [-1, 0]]
    end

    test "four CW rotations return to original coords" do
      rotated =
        @l_shape
        |> Shape.rotate(:cw)
        |> Shape.rotate(:cw)
        |> Shape.rotate(:cw)
        |> Shape.rotate(:cw)

      assert rotated.coords == @l_shape.coords
    end

    test "preserves label" do
      rotated = Shape.rotate(@l_shape, :cw)
      assert rotated.label == :test
    end

    test "works with half-integer coords (stick)" do
      rotated = Shape.rotate(@stick, :cw)
      # (0, 1.5) -> (1.5, 0), (0, 0.5) -> (0.5, 0), etc.
      assert rotated.coords == [[1.5, 0], [0.5, 0], [-0.5, 0], [-1.5, 0]]
    end
  end

  describe "rotate/2 :ccw" do
    test "rotates coords 90 degrees counter-clockwise" do
      # For a point (x, y) rotated 90° CCW: (x, y) -> (-y, x)
      shape = %Shape{coords: [[1, 0]]}
      rotated = Shape.rotate(shape, :ccw)
      assert rotated.coords == [[0, 1]]
    end

    test "rotates L-shape counter-clockwise" do
      rotated = Shape.rotate(@l_shape, :ccw)
      # (1,1) -> (-1,1), (0,1) -> (-1,0), (0,0) -> (0,0), (0,-1) -> (1,0)
      assert rotated.coords == [[-1, 1], [-1, 0], [0, 0], [1, 0]]
    end

    test "four CCW rotations return to original coords" do
      rotated =
        @l_shape
        |> Shape.rotate(:ccw)
        |> Shape.rotate(:ccw)
        |> Shape.rotate(:ccw)
        |> Shape.rotate(:ccw)

      assert rotated.coords == @l_shape.coords
    end

    test "CW then CCW returns to original" do
      rotated =
        @l_shape
        |> Shape.rotate(:cw)
        |> Shape.rotate(:ccw)

      assert rotated.coords == @l_shape.coords
    end

    test "CCW then CW returns to original" do
      rotated =
        @l_shape
        |> Shape.rotate(:ccw)
        |> Shape.rotate(:cw)

      assert rotated.coords == @l_shape.coords
    end
  end

  describe "rotate/2 with square" do
    test "square is symmetric under 90 degree rotation" do
      # A centered square should map onto itself (same set of points)
      rotated = Shape.rotate(@square, :cw)
      assert Enum.sort(rotated.coords) == Enum.sort(@square.coords)
    end
  end

end
