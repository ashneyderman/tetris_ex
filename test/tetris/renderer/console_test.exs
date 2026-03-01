defmodule Tetris.Renderer.ConsoleTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Tetris.Renderer.Console
  alias Tetris.Core.{Field, Shape}

  defp render_data(overrides \\ %{}) do
    {:ok, field} = Field.new(4, 4)

    Map.merge(
      %{
        field: field,
        current_shape: %Shape{label: :dot, coords: [[0, 0]]},
        current_shape_coords: {1, 1},
        score: 10,
        rows_cleared: 2,
        status: :live
      },
      overrides
    )
  end

  describe "render/1" do
    test "outputs score and rows cleared" do
      output = capture_io(fn -> Console.render(render_data()) end)
      assert output =~ "Score: 10"
      assert output =~ "Rows: 2"
    end

    test "outputs LIVE status when game is live" do
      output = capture_io(fn -> Console.render(render_data(%{status: :live})) end)
      assert output =~ "LIVE"
    end

    test "outputs PAUSED status when game is paused" do
      output = capture_io(fn -> Console.render(render_data(%{status: :paused})) end)
      assert output =~ "PAUSED"
    end

    test "outputs GAME OVER status when game is over" do
      output = capture_io(fn -> Console.render(render_data(%{status: :over})) end)
      assert output =~ "GAME OVER"
    end

    test "renders active shape cell with ▓" do
      output = capture_io(fn -> Console.render(render_data()) end)
      assert output =~ "▓"
    end

    test "renders captured cells with █" do
      {:ok, field} = Field.new(4, 4)
      cells = List.duplicate(List.duplicate(0, 4), 3) ++ [[1, 0, 0, 0]]
      field = %{field | cells: cells}

      # Place shape away from the captured cell
      data = render_data(%{field: field, current_shape_coords: {2, 0}})
      output = capture_io(fn -> Console.render(data) end)
      assert output =~ "█"
    end

    test "renders empty cells with ·" do
      output = capture_io(fn -> Console.render(render_data()) end)
      assert output =~ "·"
    end

    test "renders border frame" do
      output = capture_io(fn -> Console.render(render_data()) end)
      assert output =~ "+"
      assert output =~ "|"
    end

    test "returns :ok" do
      result = capture_io(fn -> send(self(), Console.render(render_data())) end)
      assert result =~ "Score"
      assert_received :ok
    end
  end
end
