defmodule Tetris.Core.FieldTest do
  use ExUnit.Case

  alias Tetris.Core.Field
  alias Tetris.Core.Shape

  # A vertical bar: 3 cells tall, 1 wide, centered at origin
  #   (0, 1)
  #   (0, 0)
  #   (0,-1)
  @bar %Shape{label: :bar, coords: [[0, 1], [0, 0], [0, -1]]}

  # The stick with half-integer coords
  @stick %Shape{label: :stick, coords: [[0, 1.5], [0, 0.5], [0, -0.5], [0, -1.5]]}

  # A square with half-integer coords
  @square %Shape{label: :square, coords: [[0.5, 0.5], [0.5, -0.5], [-0.5, -0.5], [-0.5, 0.5]]}

  # A single cell at origin
  @dot %Shape{label: :dot, coords: [[0, 0]]}

  describe "new/2" do
    test "creates a field with given dimensions" do
      assert {:ok, %Field{width: 10, height: 20}} = Field.new(10, 20)
    end

    test "cells are initialized to 0" do
      {:ok, field} = Field.new(3, 2)
      assert field.cells == [[0, 0, 0], [0, 0, 0]]
    end

    test "returns error for zero width" do
      assert {:error, _} = Field.new(0, 10)
    end

    test "returns error for zero height" do
      assert {:error, _} = Field.new(10, 0)
    end

    test "returns error for negative dimensions" do
      assert {:error, _} = Field.new(-1, 10)
      assert {:error, _} = Field.new(10, -1)
    end
  end

  describe "new/3" do
    test "creates a field with custom initial cell value" do
      {:ok, field} = Field.new(2, 2, 1)
      assert field.cells == [[1, 1], [1, 1]]
    end
  end

  describe "can_move?/4" do
    test "shape fits within empty field" do
      {:ok, field} = Field.new(5, 5)
      assert Field.can_move?(field, @dot, 2, 2)
    end

    test "shape at top-left corner" do
      {:ok, field} = Field.new(5, 5)
      assert Field.can_move?(field, @dot, 0, 0)
    end

    test "shape at bottom-right corner" do
      {:ok, field} = Field.new(5, 5)
      assert Field.can_move?(field, @dot, 4, 4)
    end

    test "returns false when shape extends past right edge" do
      {:ok, field} = Field.new(5, 5)
      refute Field.can_move?(field, @dot, 5, 2)
    end

    test "returns false when shape extends past left edge" do
      {:ok, field} = Field.new(5, 5)
      refute Field.can_move?(field, @dot, -1, 2)
    end

    test "returns false when shape extends past bottom edge" do
      {:ok, field} = Field.new(5, 5)
      refute Field.can_move?(field, @dot, 2, 5)
    end

    test "allows shape with negative y coords (above field)" do
      {:ok, field} = Field.new(5, 5)
      assert Field.can_move?(field, @bar, 2, 0)
    end

    test "returns false when cell is occupied" do
      {:ok, field} = Field.new(5, 5)
      # Place a dot at (2,2), then try to move there again
      {_, field} = Field.capture(field, @dot, 2, 2)
      refute Field.can_move?(field, @dot, 2, 2)
    end

    test "works with bar shape within bounds" do
      {:ok, field} = Field.new(5, 5)
      assert Field.can_move?(field, @bar, 2, 2)
    end

    test "returns false when bar extends past bottom" do
      {:ok, field} = Field.new(5, 5)
      # bar has y coords 1,0,-1; at coord_y=5 the lowest cell is at y=4 (ok)
      # but the top cell would be at y=6 which is past height-1=4
      refute Field.can_move?(field, @bar, 2, 5)
    end
  end

  describe "capture/4" do
    test "places shape cells into the field" do
      {:ok, field} = Field.new(3, 3)
      {count, new_field} = Field.capture(field, @dot, 1, 1)
      assert count == 0
      assert Matrix.elem(new_field.cells, 1, 1) == 1
    end

    test "does not eliminate incomplete rows" do
      {:ok, field} = Field.new(3, 3)
      {count, _} = Field.capture(field, @dot, 0, 2)
      assert count == 0
    end

    test "eliminates a complete row" do
      {:ok, field} = Field.new(3, 3)
      # Fill bottom row with a 3-wide horizontal shape
      row_shape = %Shape{coords: [[0, 0], [1, 0], [2, 0]]}
      {count, new_field} = Field.capture(field, row_shape, 0, 2)
      assert count == 1
      # After elimination, bottom row should be empty again
      assert Enum.at(new_field.cells, 2) == [0, 0, 0]
    end

    test "eliminates multiple complete rows" do
      {:ok, field} = Field.new(3, 3)
      # Fill bottom two rows
      two_rows = %Shape{
        coords: [[0, 0], [1, 0], [2, 0], [0, 1], [1, 1], [2, 1]]
      }
      {count, new_field} = Field.capture(field, two_rows, 0, 1)
      assert count == 2
      # All rows should be empty
      assert new_field.cells == [[0, 0, 0], [0, 0, 0], [0, 0, 0]]
    end

    test "field dimensions are preserved after capture" do
      {:ok, field} = Field.new(5, 5)
      {_, new_field} = Field.capture(field, @dot, 2, 2)
      assert new_field.width == 5
      assert new_field.height == 5
      assert length(new_field.cells) == 5
    end

    test "ignores shape cells with negative y coords" do
      {:ok, field} = Field.new(3, 3)
      # bar at y=0 has cells at y=1, y=0, y=-1; the y=-1 cell should be ignored
      {count, new_field} = Field.capture(field, @bar, 1, 0)
      assert count == 0
      assert Matrix.elem(new_field.cells, 0, 1) == 1
      assert Matrix.elem(new_field.cells, 1, 1) == 1
    end
  end

  describe "shift_shape/3" do
    test "shifts integer coords" do
      shifted = Field.shift_shape(@dot, 3, 4)
      assert shifted.coords == [[3, 4]]
    end

    test "shifts and snaps half-integer coords" do
      shifted = Field.shift_shape(@stick, 2, 5)
      # (0, 1.5)+( 2, 5) = (2, 6.5) -> snapped to (2, 7)
      # (0, 0.5)+(2, 5) = (2, 5.5) -> snapped to (2, 6)
      # (0,-0.5)+(2, 5) = (2, 4.5) -> snapped to (2, 5)
      # (0,-1.5)+(2, 5) = (2, 3.5) -> snapped to (2, 4)
      assert shifted.coords == [[2, 7], [2, 6], [2, 5], [2, 4]]
    end

    test "preserves label" do
      shifted = Field.shift_shape(@bar, 1, 1)
      assert shifted.label == :bar
    end

    test "shifts by zero does not change integer coords" do
      shifted = Field.shift_shape(@bar, 0, 0)
      assert shifted.coords == @bar.coords
    end
  end

  describe "starting_position/2" do
    test "centers a single-cell shape on a 10-wide field" do
      {:ok, field} = Field.new(10, 20)
      {x, y} = Field.starting_position(field, @dot)
      # shape width is 1, centered in 10 -> x = 4 (0-indexed)
      assert x == 4
      # max y is 0, so start_y = -(0+1) = -1
      assert y == -1
    end

    test "y positions shape above the field" do
      {:ok, field} = Field.new(10, 20)
      {_x, y} = Field.starting_position(field, @bar)
      # bar max y is 1, start_y = -(1+1) = -2
      assert y == -2
    end

    test "y with half-integer coords (stick)" do
      {:ok, field} = Field.new(10, 20)
      {_x, y} = Field.starting_position(field, @stick)
      # stick max y is 1.5, start_y = -(round(1.6) + 1) = -(2 + 1) = -3
      assert y == -3
    end

    test "centers stick on 10-wide field" do
      {:ok, field} = Field.new(10, 20)
      {x, _y} = Field.starting_position(field, @stick)
      # stick: all x=0, so shape_width=1, start_x = div(10-1,2) - 0 = 4
      assert x == 4
    end

    test "centers square on 10-wide field" do
      {:ok, field} = Field.new(10, 20)
      {x, _y} = Field.starting_position(field, @square)
      # square x range: -0.5 to 0.5, shape_width = round(0.6) - round(-0.6) + 1 = 1-(-1)+1 = 3
      # Hmm, let me recalculate: round(0.5+0.1)=1, round(-0.5-0.1)=-1, width=1-(-1)+1=3
      # start_x = div(10-3,2) - (-1) = 3 + 1 = 4
      assert x == 4
    end

    test "centers on odd-width field" do
      {:ok, field} = Field.new(5, 10)
      {x, _y} = Field.starting_position(field, @dot)
      # shape_width=1, start_x = div(5-1,2) - 0 = 2
      assert x == 2
    end
  end
end
