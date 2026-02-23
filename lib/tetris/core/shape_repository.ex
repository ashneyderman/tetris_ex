defmodule Tetris.Core.ShapeRepository do
  @moduledoc """
  This module defines a set of predefined `Tetris.Core.Shape`s and methods to select them.
  """
  alias Tetris.Core.Shape

  @shapes_repository [
    %Shape{label: :stick, coords: [[0, 1.5], [0, 0.5], [0, -0.5], [0, -1.5]]},
    %Shape{label: :square, coords: [[0.5, 0.5], [0.5, -0.5], [-0.5, -0.5], [-0.5, 0.5]]},
    %Shape{label: :seven, coords: [[-1, 1], [0, 1], [0, 0], [-1, 0]]},
    %Shape{label: :t, coords: [[-1, 1], [0, 1], [1, 1], [0, 0], [0, -1]]},
    %Shape{label: :s, coords: [[0, 1], [0, 0], [-1, 0], [-1, -1]]},
    %Shape{label: :s_mirrored, coords: [[0, 1], [0, 0], [1, 0], [1, -1]]},
    %Shape{label: :seven_mirrored, coords: [[1, 1], [0, 1], [0, 0], [0, -1]]}
  ]

  @doc """
  Returns a list of all pre-defined shapes.
  """
  @spec all_shapes() :: [Shape.t()]
  def all_shapes do
    @shapes_repository
  end

  @doc """
  Returns a list of all shape labels.
  """
  @spec all_labels() :: [Shape.label()]
  def all_labels do
    Enum.map(@shapes_repository, & &1.label)
  end

  @doc """
  Fetches a shape by its label.

  Returns `{:ok, shape}` if found, `:error` otherwise.
  """
  @spec fetch_by_label(Shape.label()) :: {:ok, Shape.t()} | :error
  def fetch_by_label(label) do
    case Enum.find(@shapes_repository, &(&1.label == label)) do
      nil -> :error
      shape -> {:ok, shape}
    end
  end

  @doc """
  Selects a random shape from the repository.
  """
  @spec select_random_shape() :: Shape.t()
  def select_random_shape do
    repo = all_shapes()
    idx = :rand.uniform(Enum.count(repo)) - 1
    Enum.at(repo, idx)
  end
end
