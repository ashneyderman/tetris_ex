defmodule Tetris.Core.ShapeRepositoryTest do
  use ExUnit.Case

  alias Tetris.Core.Shape
  alias Tetris.Core.ShapeRepository

  describe "all_shapes/0" do
    test "returns a non-empty list" do
      shapes = ShapeRepository.all_shapes()
      assert is_list(shapes)
      assert length(shapes) > 0
    end

    test "returns 7 shapes" do
      assert length(ShapeRepository.all_shapes()) == 7
    end

    test "each element is a Shape struct with a label and coords" do
      for shape <- ShapeRepository.all_shapes() do
        assert %Shape{label: label, coords: coords} = shape
        assert is_atom(label)
        assert label != nil
        assert is_list(coords)
        assert length(coords) > 0
      end
    end
  end

  describe "all_labels/0" do
    test "returns all 7 labels" do
      labels = ShapeRepository.all_labels()
      assert length(labels) == 7
    end

    test "contains expected labels" do
      labels = ShapeRepository.all_labels()
      for label <- [:stick, :square, :seven, :t, :s, :s_mirrored, :seven_mirrored] do
        assert label in labels
      end
    end

    test "all labels are unique" do
      labels = ShapeRepository.all_labels()
      assert length(labels) == length(Enum.uniq(labels))
    end
  end

  describe "fetch_by_label/1" do
    test "returns {:ok, shape} for a known label" do
      assert {:ok, %Shape{label: :stick}} = ShapeRepository.fetch_by_label(:stick)
    end

    test "returns :error for an unknown label" do
      assert :error = ShapeRepository.fetch_by_label(:nonexistent)
    end

    test "each label resolves to the correct shape" do
      for label <- ShapeRepository.all_labels() do
        assert {:ok, %Shape{label: ^label}} = ShapeRepository.fetch_by_label(label)
      end
    end
  end

  describe "select_random_shape/0" do
    test "returns a Shape struct" do
      shape = ShapeRepository.select_random_shape()
      assert %Shape{} = shape
    end

    test "returned shape is from the repository" do
      all = ShapeRepository.all_shapes()
      shape = ShapeRepository.select_random_shape()
      assert shape in all
    end

    test "produces different shapes over multiple calls" do
      shapes = for _ <- 1..50, do: ShapeRepository.select_random_shape()
      unique = Enum.uniq(shapes)
      assert length(unique) > 1
    end
  end
end
