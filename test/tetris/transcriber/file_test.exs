defmodule Tetris.Transcriber.FileTest do
  use ExUnit.Case

  alias Tetris.Transcriber, as: Transcriber

  @moduletag :tmp_dir
  setup %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "transcript.txt")
    {:ok, path: path}
  end

  describe "init/1" do
    test "opens a file for writing", %{path: path} do
      assert {:ok, state} = Transcriber.File.init(path: path)
      assert state.io_device != nil
      Transcriber.File.finalize(state)
    end

    test "returns error for invalid path" do
      assert {:error, _reason} = Transcriber.File.init(path: "/nonexistent/dir/file.txt")
    end
  end

  describe "record/2" do
    test "writes event to file", %{path: path} do
      {:ok, state} = Transcriber.File.init(path: path)
      {:ok, state} = Transcriber.File.record({:game, 0, :init, %{width: 10, height: 20, tick_time: 1000}}, state)
      {:ok, state} = Transcriber.File.record({:user, 100, :shift, :left}, state)
      Transcriber.File.finalize(state)

      content = File.read!(path)
      lines = String.split(content, "\n", trim: true)

      assert length(lines) == 2
      assert String.contains?(hd(lines), ":init")
      assert String.contains?(Enum.at(lines, 1), ":shift")
    end

    test "events are parseable with Code.eval_string", %{path: path} do
      {:ok, state} = Transcriber.File.init(path: path)
      event = {:game, 42, :new, :s, {5, -1}}
      {:ok, state} = Transcriber.File.record(event, state)
      Transcriber.File.finalize(state)

      content = File.read!(path)
      line = String.trim(content)
      {parsed, _bindings} = Code.eval_string(line)
      assert parsed == event
    end
  end

  describe "finalize/1" do
    test "closes the file", %{path: path} do
      {:ok, state} = Transcriber.File.init(path: path)
      assert :ok = Transcriber.File.finalize(state)
    end
  end

  describe "stream/1" do
    test "round-trips written events back via stream", %{path: path} do
      events = [
        {:game, 0, :init, %{width: 10, height: 20}},
        {:game, 0, :new, :square, {4, -1}},
        {:user, 100, :shift, :left},
        {:game, 1000, :game_over}
      ]

      {:ok, state} = Transcriber.File.init(path: path)

      state =
        Enum.reduce(events, state, fn event, acc ->
          {:ok, acc} = Transcriber.File.record(event, acc)
          acc
        end)

      Transcriber.File.finalize(state)

      streamed = Transcriber.File.stream(path: path) |> Enum.to_list()
      assert streamed == events
    end

    test "filters blank lines", %{path: path} do
      content = ~s"""
      {:game, 0, :init, %{width: 10, height: 20}}

      {:game, 100, :game_over}
      """

      File.write!(path, content)

      streamed = Transcriber.File.stream(path: path) |> Enum.to_list()
      assert length(streamed) == 2
    end

    test "supports lazy consumption with Enum.take", %{path: path} do
      events = [
        {:game, 0, :init, %{width: 10, height: 20}},
        {:game, 0, :new, :square, {4, -1}},
        {:game, 1000, :tick},
        {:game, 2000, :game_over}
      ]

      {:ok, state} = Transcriber.File.init(path: path)

      state =
        Enum.reduce(events, state, fn event, acc ->
          {:ok, acc} = Transcriber.File.record(event, acc)
          acc
        end)

      Transcriber.File.finalize(state)

      first_two = Transcriber.File.stream(path: path) |> Enum.take(2)
      assert length(first_two) == 2
      assert first_two == Enum.take(events, 2)
    end
  end
end
