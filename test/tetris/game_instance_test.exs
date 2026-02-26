defmodule Tetris.GameInstanceTest do
  use ExUnit.Case

  alias Tetris.GameInstance

  defp start_instance(opts \\ []) do
    game_id = System.unique_integer([:positive])
    opts = Keyword.merge([game_id: game_id, tick_time: 60_000], opts)
    start_supervised!({GameInstance, opts})
  end

  describe "start_link/1" do
    test "starts a game instance process" do
      pid = start_instance()
      assert Process.alive?(pid)
    end

    test "registers with game_id name" do
      game_id = System.unique_integer([:positive])
      pid = start_supervised!({GameInstance, game_id: game_id, tick_time: 60_000})
      assert pid == Process.whereis(:"game_#{game_id}")
    end
  end

  describe "initialization" do
    # init/1 sets status to :paused and returns {:continue, :start_tick}.
    # handle_continue starts the tick timer and sets status to :live.
    # By the time any call or :sys.get_state reaches the process,
    # handle_continue has already executed.

    test "status is :live after initialization completes" do
      pid = start_instance()
      assert GameInstance.status(pid) == :live
    end

    test "tick timer is set after initialization completes" do
      pid = start_instance()
      assert :sys.get_state(pid).tick_ref != nil
    end
  end

  describe "rotate/2" do
    test "rotating a shape returns {:ok, _} when placement is valid" do
      pid = start_instance(width: 10, height: 20)
      result = GameInstance.rotate(pid, :cw)
      assert {:ok, %GameInstance{}} = result
    end

    test "rotating clockwise then counter-clockwise returns to original shape" do
      pid = start_instance(width: 10, height: 20)
      original = :sys.get_state(pid).current_shape

      GameInstance.rotate(pid, :cw)
      GameInstance.rotate(pid, :ccw)

      restored = :sys.get_state(pid).current_shape
      assert original.coords == restored.coords
    end

    test "four clockwise rotations return to original shape" do
      pid = start_instance(width: 10, height: 20)
      original = :sys.get_state(pid)

      Enum.each(1..4, fn _ -> GameInstance.rotate(pid, :cw) end)

      rotated = :sys.get_state(pid)
      assert original.current_shape.coords == rotated.current_shape.coords
    end

    test "rotation does not change coordinates" do
      pid = start_instance(width: 10, height: 20)
      state_before = :sys.get_state(pid)

      GameInstance.rotate(pid, :cw)

      state_after = :sys.get_state(pid)
      assert state_before.current_shape_coords == state_after.current_shape_coords
    end
  end

  describe "shift/2" do
    test "shifting right returns {:ok, _} on a wide field" do
      pid = start_instance(width: 10, height: 20)
      result = GameInstance.shift(pid, :right)
      assert {:ok, %GameInstance{}} = result
    end

    test "shifting left returns {:ok, _} on a wide field" do
      pid = start_instance(width: 10, height: 20)
      result = GameInstance.shift(pid, :left)
      assert {:ok, %GameInstance{}} = result
    end

    test "shifting right increments x coordinate by 1" do
      pid = start_instance(width: 10, height: 20)
      {x_before, y_before} = :sys.get_state(pid).current_shape_coords

      GameInstance.shift(pid, :right)

      {x_after, y_after} = :sys.get_state(pid).current_shape_coords
      assert x_after == x_before + 1
      assert y_after == y_before
    end

    test "shifting left decrements x coordinate by 1" do
      pid = start_instance(width: 10, height: 20)
      {x_before, y_before} = :sys.get_state(pid).current_shape_coords

      GameInstance.shift(pid, :left)

      {x_after, y_after} = :sys.get_state(pid).current_shape_coords
      assert x_after == x_before - 1
      assert y_after == y_before
    end

    test "shifting does not change the current shape" do
      pid = start_instance(width: 10, height: 20)
      shape_before = :sys.get_state(pid).current_shape

      GameInstance.shift(pid, :right)

      shape_after = :sys.get_state(pid).current_shape
      assert shape_before == shape_after
    end

    test "shifting right past the edge returns {:error, :unable_to_shift}" do
      pid = start_instance(width: 10, height: 20)

      results =
        Enum.map(1..20, fn _ -> GameInstance.shift(pid, :right) end)

      assert Enum.any?(results, fn r -> r == {:error, :unable_to_shift} end)
    end

    test "shifting left past the edge returns {:error, :unable_to_shift}" do
      pid = start_instance(width: 10, height: 20)

      results =
        Enum.map(1..20, fn _ -> GameInstance.shift(pid, :left) end)

      assert Enum.any?(results, fn r -> r == {:error, :unable_to_shift} end)
    end
  end
end
