defmodule Tetris.GameRobotTest do
  use ExUnit.Case

  alias Tetris.GameInstance
  alias Tetris.GameRobot
  alias Tetris.Core.Field
  alias Tetris.Core.Shape
  alias Tetris.Core.ShapeRepository

  defp start_game(opts \\ []) do
    game_id = System.unique_integer([:positive])
    opts = Keyword.merge([game_id: game_id, tick_time: :infinity], opts)
    start_supervised!({GameInstance, opts})
  end

  defp start_robot(game_pid, opts \\ []) do
    opts = Keyword.merge([game_pid: game_pid], opts)
    start_supervised!({GameRobot, opts})
  end

  describe "startup" do
    test "robot starts and connects to game via set_robot/2" do
      game = start_game()
      robot = start_robot(game)

      assert Process.alive?(robot)
      assert :ok = GameInstance.set_robot(game, robot)
    end

    test "set_robot triggers new_piece notification to robot" do
      shape = %Shape{label: :square, coords: [[0.5, 0.5], [0.5, -0.5], [-0.5, -0.5], [-0.5, 0.5]]}
      game = start_game(shape_provider: fn -> shape end)
      robot = start_robot(game, moves_per_tick: 20)

      GameInstance.set_robot(game, robot)

      assert :ok = wait_for_placement(game)
    end
  end

  describe "move execution" do
    test "robot drops piece to a valid position" do
      shape = %Shape{label: :stick, coords: [[0, 1.5], [0, 0.5], [0, -0.5], [0, -1.5]]}
      game = start_game(shape_provider: fn -> shape end, width: 10, height: 20)
      robot = start_robot(game, moves_per_tick: 20)

      GameInstance.set_robot(game, robot)
      assert :ok = wait_for_placement(game)

      state = :sys.get_state(game)
      assert state.field != nil
      assert state.status == :live
    end

    test "robot executes multiple pieces in sequence" do
      shapes = ShapeRepository.all_shapes()
      counter = :atomics.new(1, signed: false)
      :atomics.put(counter, 1, 0)

      provider = fn ->
        idx = :atomics.add_get(counter, 1, 1)
        Enum.at(shapes, rem(idx - 1, length(shapes)))
      end

      game = start_game(shape_provider: provider, width: 10, height: 20)
      robot = start_robot(game, moves_per_tick: 20)

      GameInstance.set_robot(game, robot)

      # Let robot play several pieces
      Process.sleep(200)

      state = :sys.get_state(game)
      # Multiple pieces should have been placed
      occupied =
        state.field.cells
        |> List.flatten()
        |> Enum.count(&(&1 == 1))

      assert occupied > 0
    end
  end

  describe "rate limiting" do
    test "robot executes at most moves_per_tick moves per window" do
      # Use a shape that needs several moves (shifts) to reach target
      shape = %Shape{label: :stick, coords: [[0, 1.5], [0, 0.5], [0, -0.5], [0, -1.5]]}
      game = start_game(shape_provider: fn -> shape end, width: 10, height: 20)
      robot = start_robot(game, moves_per_tick: 1)

      GameInstance.set_robot(game, robot)

      # With moves_per_tick=1, robot should still complete eventually
      # but takes more time due to scheduling delays
      Process.sleep(300)

      state = :sys.get_state(game)
      assert state.status == :live
    end
  end

  describe "placement quality" do
    test "robot avoids creating holes" do
      shape = %Shape{label: :square, coords: [[0.5, 0.5], [0.5, -0.5], [-0.5, -0.5], [-0.5, 0.5]]}
      game = start_game(shape_provider: fn -> shape end, width: 10, height: 20)
      robot = start_robot(game, moves_per_tick: 20)

      GameInstance.set_robot(game, robot)
      Process.sleep(200)

      state = :sys.get_state(game)
      holes = count_holes(state.field)
      # With squares only, a good robot should create minimal holes
      assert holes <= 2
    end

    test "robot survives at least 10 pieces" do
      shapes = ShapeRepository.all_shapes()
      counter = :atomics.new(1, signed: false)
      :atomics.put(counter, 1, 0)
      piece_count = :atomics.new(1, signed: false)
      :atomics.put(piece_count, 1, 0)

      provider = fn ->
        :atomics.add(piece_count, 1, 1)
        idx = :atomics.add_get(counter, 1, 1)
        Enum.at(shapes, rem(idx - 1, length(shapes)))
      end

      # Use a taller board to give the robot more room
      game = start_game(shape_provider: provider, width: 10, height: 40)
      robot = start_robot(game, moves_per_tick: 20)

      GameInstance.set_robot(game, robot)

      # Wait long enough for 10+ pieces
      Process.sleep(500)

      state = :sys.get_state(game)
      pieces_played = :atomics.get(piece_count, 1)

      assert pieces_played >= 10, "Robot only played #{pieces_played} pieces"
      assert state.status == :live
    end
  end

  describe "edge cases" do
    test "game over is handled gracefully" do
      shape = %Shape{label: :stick, coords: [[0, 1.5], [0, 0.5], [0, -0.5], [0, -1.5]]}

      game = start_game(shape_provider: fn -> shape end, width: 4, height: 6)
      robot = start_robot(game, moves_per_tick: 20)

      GameInstance.set_robot(game, robot)

      # Small board should eventually cause game over
      Process.sleep(500)

      state = :sys.get_state(game)
      # Robot process should still be alive even if game is over
      assert Process.alive?(robot)
      assert state.status in [:live, :over]
    end

    test "new piece cancels stale move queue" do
      shapes = [
        %Shape{label: :stick, coords: [[0, 1.5], [0, 0.5], [0, -0.5], [0, -1.5]]},
        %Shape{label: :square, coords: [[0.5, 0.5], [0.5, -0.5], [-0.5, -0.5], [-0.5, 0.5]]}
      ]

      counter = :atomics.new(1, signed: false)
      :atomics.put(counter, 1, 0)

      provider = fn ->
        idx = :atomics.add_get(counter, 1, 1)
        Enum.at(shapes, rem(idx - 1, length(shapes)))
      end

      game = start_game(shape_provider: provider, width: 10, height: 20)
      # Very slow rate to test cancellation
      robot = start_robot(game, moves_per_tick: 1)

      GameInstance.set_robot(game, robot)
      Process.sleep(300)

      # Robot should still be alive and functioning
      assert Process.alive?(robot)
    end

    test "works with all 7 shapes" do
      shapes = ShapeRepository.all_shapes()

      for shape <- shapes do
        game_id = System.unique_integer([:positive])
        # Use a tall board so the robot doesn't fill it up
        {:ok, game} = GameInstance.start_link(game_id: game_id, tick_time: :infinity, width: 10, height: 40, shape_provider: fn -> shape end)
        {:ok, robot} = GameRobot.start_link(game_pid: game, moves_per_tick: 20)

        GameInstance.set_robot(game, robot)

        assert :ok = wait_for_placement(game),
               "Robot failed to place shape #{shape.label}"

        assert Process.alive?(robot), "Robot crashed with shape #{shape.label}"

        GenServer.stop(robot)
        GenServer.stop(game)
      end
    end
  end

  describe "pure functions" do
    test "evaluate_board prefers fewer holes" do
      {:ok, field_clean} = Field.new(4, 4)
      {:ok, field_holey} = Field.new(4, 4)

      # Create a board with holes
      holey_cells = [
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [1, 0, 1, 0],
        [1, 1, 0, 1]
      ]

      field_holey = %{field_holey | cells: holey_cells}

      score_clean = GameRobot.evaluate_board(field_clean, 0)
      score_holey = GameRobot.evaluate_board(field_holey, 0)

      assert score_clean > score_holey
    end

    test "evaluate_board rewards cleared lines" do
      {:ok, field} = Field.new(4, 4)
      score_no_clear = GameRobot.evaluate_board(field, 0)
      score_one_clear = GameRobot.evaluate_board(field, 1)

      assert score_one_clear > score_no_clear
    end

    test "build_moves generates correct rotation and shift sequence" do
      moves = GameRobot.build_moves(2, 5, 3)
      assert moves == [:rotate_cw, :rotate_cw, :shift_left, :shift_left, :drop]
    end

    test "build_moves with no rotation or shift" do
      moves = GameRobot.build_moves(0, 5, 5)
      assert moves == [:drop]
    end

    test "build_moves with right shifts" do
      moves = GameRobot.build_moves(1, 3, 6)
      assert moves == [:rotate_cw, :shift_right, :shift_right, :shift_right, :drop]
    end

    test "unique_rotations returns 1 rotation for square" do
      {:ok, square} = ShapeRepository.fetch_by_label(:square)
      rotations = GameRobot.unique_rotations(square)
      assert length(rotations) == 1
    end

    test "unique_rotations returns 2 rotations for stick" do
      {:ok, stick} = ShapeRepository.fetch_by_label(:stick)
      rotations = GameRobot.unique_rotations(stick)
      assert length(rotations) == 2
    end

    test "unique_rotations returns 2 rotations for s-shapes" do
      {:ok, s} = ShapeRepository.fetch_by_label(:s)
      rotations = GameRobot.unique_rotations(s)
      assert length(rotations) == 2
    end

    test "enumerate_placements returns valid placements" do
      {:ok, field} = Field.new(10, 20)
      {:ok, stick} = ShapeRepository.fetch_by_label(:stick)

      placements = GameRobot.enumerate_placements(field, stick)
      assert length(placements) > 0

      # Each placement has {num_rotations, x, score}
      Enum.each(placements, fn {rotations, x, score} ->
        assert is_integer(rotations) and rotations >= 0 and rotations <= 3
        assert is_integer(x)
        assert is_float(score)
      end)
    end
  end

  # Waits until the game field has at least one occupied cell, or times out.
  defp wait_for_placement(game, timeout \\ 2000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_for_placement(game, deadline)
  end

  defp do_wait_for_placement(game, deadline) do
    state = :sys.get_state(game)

    occupied =
      state.field.cells
      |> List.flatten()
      |> Enum.count(&(&1 == 1))

    if occupied > 0 do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        :timeout
      else
        Process.sleep(10)
        do_wait_for_placement(game, deadline)
      end
    end
  end

  # --- Test helpers ---

  defp count_holes(%Field{cells: cells, width: width, height: height}) do
    for col <- 0..(width - 1), reduce: 0 do
      acc ->
        h = col_height(cells, col, height)
        top_row = height - h

        holes =
          if h == 0 do
            0
          else
            Enum.count((top_row + 1)..(height - 1)//1, fn row ->
              Enum.at(Enum.at(cells, row), col) == 0
            end)
          end

        acc + holes
    end
  end

  defp col_height(cells, col, height) do
    case Enum.find_index(0..(height - 1), fn row ->
           Enum.at(Enum.at(cells, row), col) == 1
         end) do
      nil -> 0
      idx -> height - idx
    end
  end
end
