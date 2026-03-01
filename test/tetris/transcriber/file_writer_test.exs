defmodule Tetris.Transcriber.FileWriterTest do
  use ExUnit.Case

  alias Tetris.Transcriber.FileWriter

  @moduletag :tmp_dir
  setup %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "transcript.txt")
    {:ok, path: path}
  end

  describe "init/1" do
    test "opens a file for writing", %{path: path} do
      assert {:ok, state} = FileWriter.init(path: path)
      assert state.io_device != nil
      FileWriter.finalize(state)
    end

    test "returns error for invalid path" do
      assert {:error, _reason} = FileWriter.init(path: "/nonexistent/dir/file.txt")
    end
  end

  describe "record/2" do
    test "writes event to file", %{path: path} do
      {:ok, state} = FileWriter.init(path: path)
      {:ok, state} = FileWriter.record({:game, 0, :init, %{width: 10, height: 20, tick_time: 1000}}, state)
      {:ok, state} = FileWriter.record({:user, 100, :shift, :left}, state)
      FileWriter.finalize(state)

      content = File.read!(path)
      lines = String.split(content, "\n", trim: true)

      assert length(lines) == 2
      assert String.contains?(hd(lines), ":init")
      assert String.contains?(Enum.at(lines, 1), ":shift")
    end

    test "events are parseable with Code.eval_string", %{path: path} do
      {:ok, state} = FileWriter.init(path: path)
      event = {:game, 42, :new, :s, {5, -1}}
      {:ok, state} = FileWriter.record(event, state)
      FileWriter.finalize(state)

      content = File.read!(path)
      line = String.trim(content)
      {parsed, _bindings} = Code.eval_string(line)
      assert parsed == event
    end
  end

  describe "finalize/1" do
    test "closes the file", %{path: path} do
      {:ok, state} = FileWriter.init(path: path)
      assert :ok = FileWriter.finalize(state)
    end
  end
end
