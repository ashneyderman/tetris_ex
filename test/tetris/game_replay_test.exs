defmodule Tetris.GameReplayTest do
  use ExUnit.Case

  alias Tetris.GameReplay

  @moduletag :tmp_dir

  defmodule TestRenderer do
    @behaviour Tetris.Renderer

    @impl true
    def render(data) do
      send(Process.whereis(:replay_renderer_test), {:rendered, data})
      :ok
    end
  end

  defp write_transcript(tmp_dir, events) do
    path = Path.join(tmp_dir, "transcript_#{System.unique_integer([:positive])}.txt")
    content = Enum.map_join(events, "\n", &inspect/1)
    File.write!(path, content)
    path
  end

  defp simple_transcript do
    [
      {:game, 0, :init, %{width: 10, height: 20, tick_time: 1000}},
      {:game, 0, :new, :square, {4, -1}},
      {:game, 1000, :tick},
      {:game, 2000, :tick},
      {:game, 12000, :game_over}
    ]
  end

  describe "start_link and replay" do
    test "starts and replays a simple transcript", %{tmp_dir: tmp_dir} do
      path = write_transcript(tmp_dir, simple_transcript())
      game_id = System.unique_integer([:positive])

      pid = start_supervised!({GameReplay, path: path, game_id: game_id, speed: 100.0})

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000
    end

    test "registers with replay_<game_id> name", %{tmp_dir: tmp_dir} do
      path = write_transcript(tmp_dir, simple_transcript())
      game_id = System.unique_integer([:positive])

      pid = start_supervised!({GameReplay, path: path, game_id: game_id, speed: 100.0})
      assert pid == Process.whereis(:"replay_#{game_id}")

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000
    end
  end

  describe "renderer integration" do
    test "renders after each visible event", %{tmp_dir: tmp_dir} do
      Process.register(self(), :replay_renderer_test)

      events = [
        {:game, 0, :init, %{width: 10, height: 20, tick_time: 1000}},
        {:game, 0, :new, :square, {4, -1}},
        {:game, 1000, :tick},
        {:game, 2000, :game_over}
      ]

      path = write_transcript(tmp_dir, events)
      game_id = System.unique_integer([:positive])

      pid =
        start_supervised!(
          {GameReplay, path: path, game_id: game_id, speed: 100.0, renderer: TestRenderer}
        )

      ref = Process.monitor(pid)

      # We expect renders for: :new, :tick, :game_over (not :init)
      assert_receive {:rendered, %{current_shape: shape1}}, 5000
      assert shape1.label == :square

      assert_receive {:rendered, %{current_shape_coords: coords}}, 5000
      assert coords == {4, 0}

      assert_receive {:rendered, %{status: :over}}, 5000

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000
    end

    test "render data contains all expected keys", %{tmp_dir: tmp_dir} do
      Process.register(self(), :replay_renderer_test)

      events = [
        {:game, 0, :init, %{width: 10, height: 20}},
        {:game, 0, :new, :square, {4, -1}},
        {:game, 1000, :game_over}
      ]

      path = write_transcript(tmp_dir, events)
      game_id = System.unique_integer([:positive])

      pid =
        start_supervised!(
          {GameReplay, path: path, game_id: game_id, speed: 100.0, renderer: TestRenderer}
        )

      ref = Process.monitor(pid)

      assert_receive {:rendered, data}, 5000
      assert Map.has_key?(data, :field)
      assert Map.has_key?(data, :current_shape)
      assert Map.has_key?(data, :current_shape_coords)
      assert Map.has_key?(data, :score)
      assert Map.has_key?(data, :rows_cleared)
      assert Map.has_key?(data, :status)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000
    end
  end

  describe "speed control" do
    test "speed: 100.0 makes replay complete quickly", %{tmp_dir: tmp_dir} do
      events = [
        {:game, 0, :init, %{width: 10, height: 20, tick_time: 1000}},
        {:game, 0, :new, :square, {4, -1}},
        {:game, 5000, :tick},
        {:game, 10000, :game_over}
      ]

      path = write_transcript(tmp_dir, events)
      game_id = System.unique_integer([:positive])

      start = System.monotonic_time(:millisecond)

      pid = start_supervised!({GameReplay, path: path, game_id: game_id, speed: 100.0})

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000

      elapsed = System.monotonic_time(:millisecond) - start
      # 10000ms / 100.0 = 100ms, should complete well under 2 seconds
      assert elapsed < 2000
    end
  end

  describe "event processing" do
    test "shift events update coordinates", %{tmp_dir: tmp_dir} do
      Process.register(self(), :replay_renderer_test)

      events = [
        {:game, 0, :init, %{width: 10, height: 20}},
        {:game, 0, :new, :square, {4, 0}},
        {:user, 100, :shift, :left},
        {:user, 200, :shift, :right},
        {:user, 300, :shift, :right},
        {:game, 1000, :game_over}
      ]

      path = write_transcript(tmp_dir, events)
      game_id = System.unique_integer([:positive])

      pid =
        start_supervised!(
          {GameReplay, path: path, game_id: game_id, speed: 100.0, renderer: TestRenderer}
        )

      ref = Process.monitor(pid)

      # :new at {4, 0}
      assert_receive {:rendered, %{current_shape_coords: {4, 0}}}, 5000
      # shift :left -> {3, 0}
      assert_receive {:rendered, %{current_shape_coords: {3, 0}}}, 5000
      # shift :right -> {4, 0}
      assert_receive {:rendered, %{current_shape_coords: {4, 0}}}, 5000
      # shift :right -> {5, 0}
      assert_receive {:rendered, %{current_shape_coords: {5, 0}}}, 5000
      # game_over
      assert_receive {:rendered, %{status: :over}}, 5000

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000
    end

    test "rotate events update shape", %{tmp_dir: tmp_dir} do
      Process.register(self(), :replay_renderer_test)

      events = [
        {:game, 0, :init, %{width: 10, height: 20}},
        {:game, 0, :new, :s, {4, 2}},
        {:user, 100, :rotate, :cw},
        {:game, 1000, :game_over}
      ]

      path = write_transcript(tmp_dir, events)
      game_id = System.unique_integer([:positive])

      pid =
        start_supervised!(
          {GameReplay, path: path, game_id: game_id, speed: 100.0, renderer: TestRenderer}
        )

      ref = Process.monitor(pid)

      # :new — original shape
      assert_receive {:rendered, %{current_shape: original}}, 5000
      # :rotate :cw — rotated shape
      assert_receive {:rendered, %{current_shape: rotated}}, 5000
      assert original.coords != rotated.coords
      # game_over
      assert_receive {:rendered, _}, 5000

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000
    end

    test "capture_shape updates field and score", %{tmp_dir: tmp_dir} do
      Process.register(self(), :replay_renderer_test)

      # Use a tiny field and a square shape at bottom to trigger row clearing
      events = [
        {:game, 0, :init, %{width: 2, height: 4}},
        {:game, 0, :new, :square, {0, 2}},
        {:game, 100, :capture_shape},
        {:game, 100, :new, :square, {0, 0}},
        {:game, 200, :game_over}
      ]

      path = write_transcript(tmp_dir, events)
      game_id = System.unique_integer([:positive])

      pid =
        start_supervised!(
          {GameReplay, path: path, game_id: game_id, speed: 100.0, renderer: TestRenderer}
        )

      ref = Process.monitor(pid)

      # :new
      assert_receive {:rendered, _}, 5000
      # :capture_shape — square occupies 2x2 on a 2-wide field, so 2 rows cleared
      assert_receive {:rendered, %{rows_cleared: rows, score: score}}, 5000
      assert rows == 2
      assert score == 4
      # :new (second shape)
      assert_receive {:rendered, _}, 5000
      # :game_over
      assert_receive {:rendered, %{status: :over}}, 5000

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000
    end

    test "drop_shape moves shape to bottom", %{tmp_dir: tmp_dir} do
      Process.register(self(), :replay_renderer_test)

      events = [
        {:game, 0, :init, %{width: 10, height: 20}},
        {:game, 0, :new, :square, {4, 0}},
        {:user, 100, :drop_shape},
        {:game, 100, :capture_shape},
        {:game, 100, :new, :square, {4, 0}},
        {:game, 200, :game_over}
      ]

      path = write_transcript(tmp_dir, events)
      game_id = System.unique_integer([:positive])

      pid =
        start_supervised!(
          {GameReplay, path: path, game_id: game_id, speed: 100.0, renderer: TestRenderer}
        )

      ref = Process.monitor(pid)

      # :new at {4, 0}
      assert_receive {:rendered, %{current_shape_coords: {4, 0}}}, 5000
      # :drop_shape — square should be at the bottom
      # Square coords are roughly [[-0.5,-0.5],[0.5,-0.5],[-0.5,0.5],[0.5,0.5]]
      # so max_y ≈ 0.5, bottom = height - 1 - round(0.5) = 18, so y=18
      assert_receive {:rendered, %{current_shape_coords: {4, dropped_y}}}, 5000
      assert dropped_y > 0

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000
    end
  end

  describe "game over stops the process" do
    test "process terminates normally after :game_over", %{tmp_dir: tmp_dir} do
      events = [
        {:game, 0, :init, %{width: 10, height: 20}},
        {:game, 0, :new, :square, {4, -1}},
        {:game, 100, :game_over}
      ]

      path = write_transcript(tmp_dir, events)
      game_id = System.unique_integer([:positive])

      pid = start_supervised!({GameReplay, path: path, game_id: game_id, speed: 100.0})

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000
    end

    test "process terminates normally when events are exhausted", %{tmp_dir: tmp_dir} do
      events = [
        {:game, 0, :init, %{width: 10, height: 20}},
        {:game, 0, :new, :square, {4, -1}},
        {:game, 100, :tick}
      ]

      path = write_transcript(tmp_dir, events)
      game_id = System.unique_integer([:positive])

      pid = start_supervised!({GameReplay, path: path, game_id: game_id, speed: 100.0})

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000
    end
  end
end
