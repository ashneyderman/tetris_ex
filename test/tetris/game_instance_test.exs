defmodule Tetris.GameInstanceTest do
  use ExUnit.Case

  alias Tetris.GameInstance
  alias Tetris.Core.Field
  alias Tetris.Core.Shape

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

  describe "drop_shape/1" do
    test "drop_shape returns :ok on a live game" do
      pid = start_instance(width: 10, height: 20)
      assert :ok = GameInstance.drop_shape(pid)
    end

    test "drop_shape returns {:error, :game_over} when game is over" do
      pid = start_instance()
      :sys.replace_state(pid, fn state -> %{state | status: :over} end)

      assert {:error, :game_over} = GameInstance.drop_shape(pid)
    end

    test "drop_shape returns {:error, :paused} when game is paused" do
      pid = start_instance()
      GameInstance.pause(pid)

      assert {:error, :paused} = GameInstance.drop_shape(pid)
    end

    test "drop_shape cancels the current tick timer" do
      pid = start_instance(width: 10, height: 20)
      old_ref = :sys.get_state(pid).tick_ref
      assert old_ref != nil

      GameInstance.drop_shape(pid)

      new_ref = :sys.get_state(pid).tick_ref
      assert new_ref != old_ref
    end

    test "drop_shape captures the shape and spawns a new one" do
      pid = start_instance(width: 10, height: 20)
      state = :sys.get_state(pid)
      GameInstance.drop_shape(pid)

      new_state = :sys.get_state(pid)
      # New shape is at its starting position
      {new_x, new_y} = new_state.current_shape_coords
      {expected_x, expected_y} = Field.starting_position(new_state.field, new_state.current_shape)
      assert new_x == expected_x
      assert new_y == expected_y
      # The field should have changed (shape was captured)
      assert new_state.field != state.field
    end

    test "drop_shape places shape at the bottom of the field" do
      pid = start_instance(width: 10, height: 20)
      GameInstance.drop_shape(pid)

      new_state = :sys.get_state(pid)
      # The old shape's cells should now be at the bottom of the field
      # Check that the bottom rows of the field have some occupied cells
      bottom_row = Enum.at(new_state.field.cells, new_state.field.height - 1)
      assert Enum.any?(bottom_row, fn cell -> cell == 1 end)
    end

    test "drop_shape starts a new tick timer" do
      pid = start_instance(width: 10, height: 20)

      GameInstance.drop_shape(pid)

      new_state = :sys.get_state(pid)
      assert new_state.tick_ref != nil
      assert new_state.status == :live
    end

    test "drop_shape results in game over when field is nearly full" do
      pid = start_instance(width: 10, height: 20)
      state = :sys.get_state(pid)
      {x, _y} = state.current_shape_coords

      # Fill entire field except row 0 — shape starts above field,
      # dropping lands it at row 0 or above, triggering game over.
      :sys.replace_state(pid, fn s ->
        %{s |
          current_shape_coords: {x, 0},
          field: fill_field_except_top_row(s.field)
        }
      end)

      assert :ok = GameInstance.drop_shape(pid)

      new_state = :sys.get_state(pid)
      assert new_state.status == :over
      assert new_state.tick_ref == nil
    end

    test "drop_shape keeps status :live when shape lands safely" do
      pid = start_instance(width: 10, height: 20)

      GameInstance.drop_shape(pid)

      assert :sys.get_state(pid).status == :live
    end
  end

  describe "scoring" do
    test "score and rows_cleared start at 0" do
      pid = start_instance(width: 10, height: 20)
      state = :sys.get_state(pid)
      assert state.score == 0
      assert state.rows_cleared == 0
    end

    test "drop that clears no rows does not change score" do
      pid = start_instance(width: 10, height: 20)

      GameInstance.drop_shape(pid)

      state = :sys.get_state(pid)
      assert state.score == 0
      assert state.rows_cleared == 0
    end

    test "drop that clears 1 row adds 1 to score" do
      pid = start_instance(width: 4, height: 6)

      # Use a single-cell shape and fill all but one cell in the bottom row
      dot = %Shape{label: :dot, coords: [[0, 0]]}

      :sys.replace_state(pid, fn s ->
        cells =
          List.duplicate(List.duplicate(0, 4), 5) ++
            [[1, 1, 1, 0]]

        %{s |
          current_shape: dot,
          current_shape_coords: {3, 0},
          field: %{s.field | cells: cells}
        }
      end)

      GameInstance.drop_shape(pid)

      state = :sys.get_state(pid)
      assert state.rows_cleared == 1
      assert state.score == 1
    end

    test "drop that clears 2 rows adds 4 to score" do
      pid = start_instance(width: 4, height: 6)

      # A 2-cell tall shape to complete 2 rows at once
      bar = %Shape{label: :bar, coords: [[0, 0], [0, 1]]}

      :sys.replace_state(pid, fn s ->
        cells =
          List.duplicate(List.duplicate(0, 4), 4) ++
            [[1, 1, 1, 0], [1, 1, 1, 0]]

        %{s |
          current_shape: bar,
          current_shape_coords: {3, 0},
          field: %{s.field | cells: cells}
        }
      end)

      GameInstance.drop_shape(pid)

      state = :sys.get_state(pid)
      assert state.rows_cleared == 2
      assert state.score == 4
    end

    test "score accumulates across multiple drops" do
      pid = start_instance(width: 4, height: 6)
      dot = %Shape{label: :dot, coords: [[0, 0]]}

      # First drop: clears 1 row (score += 1)
      :sys.replace_state(pid, fn s ->
        cells =
          List.duplicate(List.duplicate(0, 4), 5) ++
            [[1, 1, 1, 0]]

        %{s |
          current_shape: dot,
          current_shape_coords: {3, 0},
          field: %{s.field | cells: cells}
        }
      end)

      GameInstance.drop_shape(pid)

      assert :sys.get_state(pid).score == 1
      assert :sys.get_state(pid).rows_cleared == 1

      # Second drop: clears 1 more row (score += 1, total 2)
      :sys.replace_state(pid, fn s ->
        cells =
          List.duplicate(List.duplicate(0, 4), 5) ++
            [[1, 1, 1, 0]]

        %{s |
          current_shape: dot,
          current_shape_coords: {3, 0},
          field: %{s.field | cells: cells}
        }
      end)

      GameInstance.drop_shape(pid)

      assert :sys.get_state(pid).score == 2
      assert :sys.get_state(pid).rows_cleared == 2
    end

    test "tick that captures shape also updates score" do
      pid = start_instance(width: 4, height: 6)
      dot = %Shape{label: :dot, coords: [[0, 0]]}

      :sys.replace_state(pid, fn s ->
        cells =
          List.duplicate(List.duplicate(0, 4), 5) ++
            [[1, 1, 1, 0]]

        # Place dot at bottom row so next tick can't move down, triggering capture
        %{s |
          current_shape: dot,
          current_shape_coords: {3, 5},
          field: %{s.field | cells: cells}
        }
      end)

      send_tick(pid)

      state = :sys.get_state(pid)
      assert state.rows_cleared == 1
      assert state.score == 1
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

  describe "renderer integration" do
    defmodule TestRenderer do
      @behaviour Tetris.Renderer

      @impl true
      def render(data) do
        send(Process.whereis(:renderer_test), {:rendered, data})
        :ok
      end
    end

    defp start_rendered_instance(opts \\ []) do
      Process.register(self(), :renderer_test)
      game_id = System.unique_integer([:positive])
      opts = Keyword.merge([game_id: game_id, tick_time: 60_000, renderer: TestRenderer], opts)
      start_supervised!({GameInstance, opts})
    end

    test "render is called after init (handle_continue)" do
      _pid = start_rendered_instance()
      assert_receive {:rendered, data}, 500
      assert data.status == :live
    end

    test "render data contains all expected keys" do
      _pid = start_rendered_instance()
      assert_receive {:rendered, data}, 500

      assert Map.has_key?(data, :field)
      assert Map.has_key?(data, :current_shape)
      assert Map.has_key?(data, :current_shape_coords)
      assert Map.has_key?(data, :score)
      assert Map.has_key?(data, :rows_cleared)
      assert Map.has_key?(data, :status)
    end

    test "render is called after successful shift" do
      pid = start_rendered_instance(width: 10, height: 20)
      assert_receive {:rendered, _}, 500

      GameInstance.shift(pid, :right)
      assert_receive {:rendered, _}, 500
    end

    test "render is NOT called on failed shift" do
      pid = start_rendered_instance(width: 10, height: 20)
      assert_receive {:rendered, _}, 500

      # Shift right until blocked
      Enum.each(1..20, fn _ -> GameInstance.shift(pid, :right) end)
      # Drain all render messages
      drain_renders()

      # Now try one more shift that should fail
      assert {:error, :unable_to_shift} = GameInstance.shift(pid, :right)
      refute_receive {:rendered, _}, 100
    end

    test "render is called after successful rotate" do
      pid = start_rendered_instance(width: 10, height: 20)
      assert_receive {:rendered, _}, 500

      GameInstance.rotate(pid, :cw)
      assert_receive {:rendered, _}, 500
    end

    test "render is called after drop_shape" do
      pid = start_rendered_instance(width: 10, height: 20)
      assert_receive {:rendered, _}, 500

      GameInstance.drop_shape(pid)
      assert_receive {:rendered, _}, 500
    end

    test "render is called after pause" do
      pid = start_rendered_instance()
      assert_receive {:rendered, _}, 500

      GameInstance.pause(pid)
      assert_receive {:rendered, data}, 500
      assert data.status == :paused
    end

    test "render is called after unpause" do
      pid = start_rendered_instance()
      assert_receive {:rendered, _}, 500

      GameInstance.pause(pid)
      assert_receive {:rendered, _}, 500

      GameInstance.unpause(pid)
      assert_receive {:rendered, data}, 500
      assert data.status == :live
    end

    test "render is called on tick" do
      pid = start_rendered_instance(width: 10, height: 20)
      assert_receive {:rendered, _}, 500

      send(pid, :tick)
      _ = :sys.get_state(pid)
      assert_receive {:rendered, _}, 500
    end

    test "backward compatibility: no renderer option causes no errors" do
      game_id = System.unique_integer([:positive])
      pid = start_supervised!({GameInstance, game_id: game_id, tick_time: 60_000})
      assert Process.alive?(pid)
      assert GameInstance.status(pid) == :live
    end

    defp drain_renders do
      receive do
        {:rendered, _} -> drain_renders()
      after
        0 -> :ok
      end
    end
  end

  describe "shape_provider" do
    test "uses custom shape_provider instead of random" do
      shape = %Shape{label: :stick, coords: [[0, 1.5], [0, 0.5], [0, -0.5], [0, -1.5]]}
      provider = fn -> shape end

      pid = start_instance(width: 10, height: 20, shape_provider: provider)
      state = :sys.get_state(pid)

      assert state.current_shape.label == :stick
    end

    test "shape_provider is called for new shapes after drop" do
      shapes = [
        %Shape{label: :square, coords: [[0.5, 0.5], [0.5, -0.5], [-0.5, -0.5], [-0.5, 0.5]]},
        %Shape{label: :stick, coords: [[0, 1.5], [0, 0.5], [0, -0.5], [0, -1.5]]}
      ]

      counter = :atomics.new(1, signed: false)
      :atomics.put(counter, 1, 0)

      provider = fn ->
        idx = :atomics.add_get(counter, 1, 1)
        Enum.at(shapes, idx - 1, hd(shapes))
      end

      pid = start_instance(width: 10, height: 20, shape_provider: provider)
      state = :sys.get_state(pid)
      assert state.current_shape.label == :square

      GameInstance.drop_shape(pid)
      new_state = :sys.get_state(pid)
      assert new_state.current_shape.label == :stick
    end
  end

  describe "transcriber integration" do
    defmodule TestTranscriber do
      @behaviour Tetris.Transcriber

      @impl true
      def init(opts) do
        pid = Keyword.fetch!(opts, :test_pid)
        {:ok, %{events: [], test_pid: pid}}
      end

      @impl true
      def record(event, state) do
        {:ok, %{state | events: state.events ++ [event]}}
      end

      @impl true
      def finalize(state) do
        send(state.test_pid, {:transcriber_events, state.events})
        :ok
      end
    end

    defp start_transcribed_instance(opts \\ []) do
      game_id = System.unique_integer([:positive])
      shape = %Shape{label: :square, coords: [[0.5, 0.5], [0.5, -0.5], [-0.5, -0.5], [-0.5, 0.5]]}
      provider = fn -> shape end

      opts =
        Keyword.merge(
          [
            game_id: game_id,
            tick_time: 60_000,
            shape_provider: provider,
            transcriber: {TestTranscriber, [test_pid: self()]}
          ],
          opts
        )

      start_supervised!({GameInstance, opts})
    end

    test "init records :init and :new events" do
      pid = start_transcribed_instance()
      {_mod, transcriber_state} = :sys.get_state(pid).transcriber

      assert length(transcriber_state.events) == 2
      assert {:game, _, :init, %{width: 10, height: 20, tick_time: 60_000}} = Enum.at(transcriber_state.events, 0)
      assert {:game, _, :new, :square, _coords} = Enum.at(transcriber_state.events, 1)
    end

    test "shift records :shift event" do
      pid = start_transcribed_instance(width: 10, height: 20)
      GameInstance.shift(pid, :left)

      {_mod, transcriber_state} = :sys.get_state(pid).transcriber
      shift_events = Enum.filter(transcriber_state.events, fn e -> elem(e, 2) == :shift end)
      assert length(shift_events) == 1
      assert {:user, _, :shift, :left} = hd(shift_events)
    end

    test "rotate records :rotate event" do
      pid = start_transcribed_instance(width: 10, height: 20)
      GameInstance.rotate(pid, :cw)

      {_mod, transcriber_state} = :sys.get_state(pid).transcriber
      rotate_events = Enum.filter(transcriber_state.events, fn e -> elem(e, 2) == :rotate end)
      assert length(rotate_events) == 1
      assert {:user, _, :rotate, :cw} = hd(rotate_events)
    end

    test "drop_shape records :drop_shape, :capture_shape, and :new events" do
      pid = start_transcribed_instance(width: 10, height: 20)
      GameInstance.drop_shape(pid)

      {_mod, transcriber_state} = :sys.get_state(pid).transcriber
      event_types = Enum.map(transcriber_state.events, fn e -> elem(e, 2) end)

      assert :drop_shape in event_types
      assert :capture_shape in event_types
      # Should have 2 :new events (init + after capture)
      assert Enum.count(event_types, &(&1 == :new)) == 2
    end

    test "tick records :tick event" do
      pid = start_transcribed_instance(width: 10, height: 20)
      send(pid, :tick)
      _ = :sys.get_state(pid)

      {_mod, transcriber_state} = :sys.get_state(pid).transcriber
      tick_events = Enum.filter(transcriber_state.events, fn e -> elem(e, 2) == :tick end)
      assert length(tick_events) == 1
    end

    test "finalize is called on terminate" do
      pid = start_transcribed_instance(width: 10, height: 20)
      GameInstance.drop_shape(pid)

      GenServer.stop(pid)
      assert_receive {:transcriber_events, events}, 500
      assert length(events) > 0
    end

    test "time offsets are non-negative integers" do
      pid = start_transcribed_instance(width: 10, height: 20)
      GameInstance.shift(pid, :left)
      GameInstance.rotate(pid, :cw)

      {_mod, transcriber_state} = :sys.get_state(pid).transcriber

      Enum.each(transcriber_state.events, fn event ->
        offset = elem(event, 1)
        assert is_integer(offset)
        assert offset >= 0
      end)
    end

    test "backward compatibility: no transcriber option causes no errors" do
      game_id = System.unique_integer([:positive])
      pid = start_supervised!({GameInstance, game_id: game_id, tick_time: 60_000})
      assert Process.alive?(pid)
      assert GameInstance.status(pid) == :live

      state = :sys.get_state(pid)
      assert state.transcriber == nil
    end
  end

  describe "maybe_schedule_tick/1" do
    test "tick_time :infinity does not schedule tick" do
      shape = %Shape{label: :square, coords: [[0.5, 0.5], [0.5, -0.5], [-0.5, -0.5], [-0.5, 0.5]]}
      provider = fn -> shape end

      pid = start_instance(width: 10, height: 20, tick_time: :infinity, shape_provider: provider)
      state = :sys.get_state(pid)

      assert state.tick_ref == nil
      assert state.status == :live
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
