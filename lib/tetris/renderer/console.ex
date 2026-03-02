defmodule Tetris.Renderer.Console do
  @moduledoc """
  Terminal renderer using IO.ANSI for colorized, in-place output.

  Renders the Tetris field with:
  - `█` (yellow) for captured cells
  - `▓` (cyan) for the active falling shape
  - `·` for empty cells
  - A bordered frame and status/score line
  """

  @behaviour Tetris.Renderer

  @impl true
  def render(data) do
    %{
      field: field,
      current_shape: shape,
      current_shape_coords: {offset_x, offset_y},
      score: score,
      rows_cleared: rows_cleared,
      status: status,
      start_time: start_time
    } = data

    shape_cells = shape_cell_set(shape, offset_x, offset_y)

    border = "+" <> String.duplicate("--", field.width) <> "+"

    above_rows =
      for y <- -4..-1 do
        cells =
          for x <- 0..(field.width - 1) do
            if MapSet.member?(shape_cells, {x, y}) do
              IO.ANSI.cyan() <> "▓ " <> IO.ANSI.reset()
            else
              "  "
            end
          end
          |> Enum.join()

        " " <> cells
      end

    field_rows =
      field.cells
      |> Enum.with_index()
      |> Enum.map(fn {row, y} ->
        cells =
          row
          |> Enum.with_index()
          |> Enum.map(fn {cell, x} ->
            cond do
              MapSet.member?(shape_cells, {x, y}) ->
                IO.ANSI.cyan() <> "▓ " <> IO.ANSI.reset()

              cell == 1 ->
                IO.ANSI.yellow() <> "█ " <> IO.ANSI.reset()

              true ->
                "· "
            end
          end)
          |> Enum.join()

        "|" <> cells <> "|"
      end)

    total_seconds_elapsed = round((System.monotonic_time(:millisecond) - start_time) / 1000)
    status_line = format_status(status)
    score_line = "Score: #{score}  Rows: #{rows_cleared}  Time: #{total_seconds_elapsed} sec"

    output =
      IO.ANSI.clear() <>
        IO.ANSI.home() <>
        Enum.join(above_rows ++ field_rows ++ [border, status_line, score_line], "\n") <>
        "\n"

    IO.write(output)
    :ok
  end

  defp shape_cell_set(%{coords: coords}, offset_x, offset_y) do
    coords
    |> Enum.map(fn [x, y] ->
      {round(x + offset_x + 0.1), round(y + offset_y + 0.1)}
    end)
    |> MapSet.new()
  end

  defp format_status(:live),
    do: IO.ANSI.green() <> "LIVE" <> IO.ANSI.reset()

  defp format_status(:paused),
    do: IO.ANSI.yellow() <> "PAUSED" <> IO.ANSI.reset()

  defp format_status(:over),
    do: IO.ANSI.red() <> "GAME OVER" <> IO.ANSI.reset()
end
