defmodule MatrixUtils do
  @moduledoc """
  Some of the `Matrix` dependency missing utils.
  """

  @doc """
  Applies given function to each of the cells in the matrix.
  """
  @spec apply_each_cell(Matrix.matrix(), fun()) :: Matrix.matrix()
  def apply_each_cell(matrix, fun) when is_list(matrix) and is_function(fun, 1) do
    matrix
    |> Enum.map(fn row ->
      Enum.map(row, fn cell -> fun.(cell) end)
    end)
  end
end
