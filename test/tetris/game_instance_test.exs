defmodule Tetris.GameInstanceTest do
  use ExUnit.Case

  alias Tetris.GameInstance
  alias Tetris.Core.Field

  defp start_instance(opts \\ []) do
    game_id = System.unique_integer([:positive])
    opts = Keyword.merge([game_id: game_id, tick_time: 60_000], opts)
    start_supervised!({GameInstance, opts})
  end

  # Sends a :tick message and waits for it to be processed by
  # making a synchronous call afterwards.
  defp send_tick(pid) do
    send(pid, :tick)
    _ = :sys.get_state(pid)
    :ok
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

  describe "pause/1" do
    test "pausing a live game sets status to :paused" do
      pid = start_instance()
      assert GameInstance.status(pid) == :live

      assert :ok = GameInstance.pause(pid)
      assert GameInstance.status(pid) == :paused
    end

    test "pausing cancels the tick timer" do
      pid = start_instance()
      assert :sys.get_state(pid).tick_ref != nil

      GameInstance.pause(pid)

      assert :sys.get_state(pid).tick_ref == nil
    end

    test "pausing an already paused game is a no-op" do
      pid = start_instance()
      GameInstance.pause(pid)

      assert :ok = GameInstance.pause(pid)
      assert GameInstance.status(pid) == :paused
    end

    test "pausing a game over game returns {:error, :game_over}" do
      pid = start_instance()
      :sys.replace_state(pid, fn state -> %{state | status: :over} end)

      assert {:error, :game_over} = GameInstance.pause(pid)
      assert :sys.get_state(pid).status == :over
    end
  end

  describe "unpause/1" do
    test "unpausing a paused game sets status to :live" do
      pid = start_instance()
      GameInstance.pause(pid)
      assert GameInstance.status(pid) == :paused

      assert :ok = GameInstance.unpause(pid)
      assert GameInstance.status(pid) == :live
    end

    test "unpausing starts a new tick timer" do
      pid = start_instance()
      GameInstance.pause(pid)
      assert :sys.get_state(pid).tick_ref == nil

      GameInstance.unpause(pid)

      assert :sys.get_state(pid).tick_ref != nil
    end

    test "unpausing an already live game is a no-op" do
      pid = start_instance()
      assert GameInstance.status(pid) == :live

      assert :ok = GameInstance.unpause(pid)
      assert GameInstance.status(pid) == :live
    end

    test "unpausing a game over game returns {:error, :game_over}" do
      pid = start_instance()
      :sys.replace_state(pid, fn state -> %{state | status: :over} end)

      assert {:error, :game_over} = GameInstance.unpause(pid)
      assert :sys.get_state(pid).status == :over
    end

    test "pause then unpause restores a working tick timer" do
      pid = start_instance()
      old_ref = :sys.get_state(pid).tick_ref

      GameInstance.pause(pid)
      GameInstance.unpause(pid)

      new_ref = :sys.get_state(pid).tick_ref
      assert new_ref != nil
      assert new_ref != old_ref
    end
  end

  describe "tick handler" do
    test "tick moves shape down by 1 when placement is valid" do
      pid = start_instance(width: 10, height: 20)
      {_x, y_before} = :sys.get_state(pid).current_shape_coords

      send_tick(pid)

      {_x, y_after} = :sys.get_state(pid).current_shape_coords
      assert y_after == y_before + 1
    end

    test "tick preserves x coordinate" do
      pid = start_instance(width: 10, height: 20)
      {x_before, _y} = :sys.get_state(pid).current_shape_coords

      send_tick(pid)

      {x_after, _y} = :sys.get_state(pid).current_shape_coords
      assert x_after == x_before
    end

    test "tick schedules a new tick timer" do
      pid = start_instance(width: 10, height: 20)
      old_ref = :sys.get_state(pid).tick_ref

      send_tick(pid)

      new_ref = :sys.get_state(pid).tick_ref
      assert new_ref != nil
      assert new_ref != old_ref
    end

    test "tick keeps status as :live when shape moves down" do
      pid = start_instance(width: 10, height: 20)

      send_tick(pid)

      assert :sys.get_state(pid).status == :live
    end

    test "shape is captured and new shape spawned when it cannot move down" do
      pid = start_instance(width: 10, height: 20)
      state = :sys.get_state(pid)
      shape = state.current_shape
      {x, _y} = state.current_shape_coords

      # Position the shape so the next tick would push it past the bottom.
      # Find the max y in the shape coords, then set offset so max_y + offset + 1 == height
      max_shape_y =
        shape.coords
        |> Enum.map(fn [_sx, sy] -> round(sy + 0.1) end)
        |> Enum.max()

      bottom_y = state.field.height - 1 - max_shape_y

      :sys.replace_state(pid, fn s ->
        %{s | current_shape_coords: {x, bottom_y}}
      end)

      send_tick(pid)

      new_state = :sys.get_state(pid)
      # A new shape should have been spawned — coords reset to starting position
      {new_x, new_y} = new_state.current_shape_coords
      {expected_x, expected_y} = Field.starting_position(new_state.field, new_state.current_shape)
      assert new_x == expected_x
      assert new_y == expected_y
      assert new_state.status == :live
      assert new_state.tick_ref != nil
    end

    test "game over when shape cannot move down and sits at or above row 0" do
      pid = start_instance(width: 10, height: 20)
      {x, _y} = :sys.get_state(pid).current_shape_coords

      # Place shape at y=0 so its cells are at or above row 0.
      # The shape can't move down because we'll fill the row below.
      # When can_place? fails at y+1=1, the game_over? check sees cells at y<=0.
      :sys.replace_state(pid, fn s ->
        %{s | current_shape_coords: {x, 0}, field: fill_field_except_top_row(s.field)}
      end)

      send_tick(pid)

      new_state = :sys.get_state(pid)
      assert new_state.status == :over
      assert new_state.tick_ref == nil
    end

    test "multiple ticks move shape progressively downward" do
      pid = start_instance(width: 10, height: 20)
      {_x, y_start} = :sys.get_state(pid).current_shape_coords

      send_tick(pid)
      send_tick(pid)
      send_tick(pid)

      {_x, y_after} = :sys.get_state(pid).current_shape_coords
      assert y_after == y_start + 3
    end

    test "tick does not change the current shape identity while falling" do
      pid = start_instance(width: 10, height: 20)
      shape_before = :sys.get_state(pid).current_shape

      send_tick(pid)

      shape_after = :sys.get_state(pid).current_shape
      assert shape_before == shape_after
    end
  end

  # Fills all rows of the field with 1s except the top row (row 0).
  defp fill_field_except_top_row(%Field{width: width, height: height} = field) do
    cells =
      for row <- 0..(height - 1) do
        if row == 0, do: List.duplicate(0, width), else: List.duplicate(1, width)
      end

    %Field{field | cells: cells}
  end
end
