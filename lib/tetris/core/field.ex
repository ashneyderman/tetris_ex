defmodule Tetris.Core.Field do
  @moduledoc """
  This module is a collection of game related operations.
  """
  alias MatrixUtils
  alias Tetris.Core.Field
  alias Tetris.Core.Shape

  @type cell_val :: 0 | 1

  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          cells: Matrix.matrix()
        }

  defstruct height: 0,
            width: 0,
            cells: []

  @doc """
  Creates a new field.

  Width and hieght have to be positive integers greater than zero.
  """
  @spec new(pos_integer(), pos_integer(), cell_val()) :: {:ok, Field.t()} | {:error, term()}
  def new(width, height, initial_cell_value \\ 0)

  def new(width, height, initial_cell_value)
      when is_integer(width) and is_integer(height) and width > 0 and height > 0 do
    {:ok,
     %Field{
       width: width,
       height: height,
       cells: Matrix.new(height, width, initial_cell_value)
     }}
  end

  def new(_, _, _) do
    {:error,
     "Unable to create the field. Width and height have to be positive integer numbers greater than 0."}
  end

  @doc """
  Captures shape's cells inside the field and eliminates rows
  that are filled.

  The content of the shape's cells will be transferred to the cells
  of the field at the given field coordinates and filled rows of the
  field will be eliminated.

  Method returns a tuple where the first element is the number of
  rows that were eliminated during the capture and second element is
  the new instance of the field.
  """
  @spec capture(Field.t(), Shape.t(), number(), number()) :: {non_neg_integer(), Field.t()}
  def capture(field = %Field{}, shape = %Shape{}, coord_x, coord_y) do
    shifted_shape = shift_shape(shape, coord_x, coord_y)

    {count, swept_field_reversed} =
      shifted_shape.coords
      |> Enum.reduce(field.cells, fn [x, y], field_cells ->
        if y < 0 do
          field_cells
        else
          Matrix.set(field_cells, y, x, 1)
        end
      end)
      |> Enum.reduce({0, []}, fn row, {count, acc} ->
        if Enum.all?(row, fn c -> c == 1 end) do
          {count + 1, acc}
        else
          {count, [row | acc]}
        end
      end)

    new_cells =
      swept_field_reversed
      |> Enum.reverse()
      |> prepend_empty_rows(count, field.width)

    {count, %Field{field | cells: new_cells}}
  end

  @doc """
  Checks if shape can be placed at the given coordinates.

  Returns true if no interference from occupied cells detected and
  shape still stays within the field's bounds; returns false otherwise.
  """
  @spec can_place?(Field.t(), Shape.t(), number(), number()) :: boolean()
  def can_place?(field, shape, coord_x, coord_y) do
    max_y = field.height - 1
    min_x = 0
    max_x = field.width - 1

    shifted_shape = shift_shape(shape, coord_x, coord_y)

    Enum.all?(shifted_shape.coords, fn [x, y] ->
      x <= max_x &&
        x >= min_x &&
        y <= max_y &&
        ((y >= 0 && Matrix.elem(field.cells, y, x) == 0) ||
           y < 0)
    end)
  end

  @doc """
  Calculates the starting position `{x, y}` for a shape on this field.

  The shape is centered horizontally within the field and positioned just
  above the top edge so that no part of the shape is visible initially.
  """
  @spec starting_position(Field.t(), Shape.t()) :: {integer(), integer()}
  def starting_position(%Field{width: width}, %Shape{coords: coords}) do
    {xs, ys} = coords |> Enum.reduce({[], []}, fn [x, y], {xs, ys} -> {[x | xs], [y | ys]} end)

    max_y = Enum.max(ys)
    start_y = -1 * (round(max_y + 0.1) + 1)

    min_x = Enum.min(xs)
    max_x = Enum.max(xs)
    shape_width = round(max_x + 0.1) - round(min_x - 0.1) + 1
    start_x = div(width - shape_width, 2) - round(min_x - 0.1)

    {start_x, start_y}
  end

  @doc """
  Pretty prints cell contents of the field.
  """
  @spec pretty_print(Field.t()) :: atom()
  def pretty_print(%Field{cells: cells}) do
    Matrix.pretty_print(cells)
  end

  # --- Helper methods ---

  @spec prepend_empty_rows(Matrix.matrix(), non_neg_integer(), pos_integer()) :: Matrix.matrix()
  defp prepend_empty_rows(cells, 0, _width), do: cells

  defp prepend_empty_rows(cells, rows, width) do
    empty_row = List.duplicate(0, width)
    Enum.reduce(1..rows, cells, fn _, acc -> [empty_row | acc] end)
  end

  @spec shift_shape(Shape.t(), number(), number()) :: Shape.t()
  defp shift_shape(%Shape{coords: coords} = shape, delta_x, delta_y) do
    shift_matrix = Enum.map(coords, fn _ -> [delta_x, delta_y] end)

    new_coords =
      coords
      |> Matrix.add(shift_matrix)
      |> snap()

    %Shape{shape | coords: new_coords}
  end

  @spec snap(Matrix.matrix()) :: Matrix.matrix()
  defp snap(coords),
    do: MatrixUtils.apply_each_cell(coords, fn cell -> round(cell + 0.1) end)
end
