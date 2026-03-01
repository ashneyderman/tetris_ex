defmodule Tetris.TranscriberTest do
  use ExUnit.Case

  alias Tetris.Transcriber

  defmodule TestTranscriber do
    @behaviour Tetris.Transcriber

    @impl true
    def init(opts) do
      {:ok, %{events: [], opts: opts}}
    end

    @impl true
    def record(event, state) do
      {:ok, %{state | events: state.events ++ [event]}}
    end

    @impl true
    def finalize(state) do
      send(Process.whereis(:transcriber_test), {:finalized, state})
      :ok
    end
  end

  describe "maybe_record/2" do
    test "returns nil when transcriber is nil" do
      assert Transcriber.maybe_record(nil, {:game, 0, :tick}) == nil
    end

    test "records event and returns updated {mod, state}" do
      {:ok, state} = TestTranscriber.init([])
      {mod, new_state} = Transcriber.maybe_record({TestTranscriber, state}, {:game, 0, :tick})

      assert mod == TestTranscriber
      assert new_state.events == [{:game, 0, :tick}]
    end

    test "accumulates multiple events" do
      {:ok, state} = TestTranscriber.init([])

      {mod, state} = Transcriber.maybe_record({TestTranscriber, state}, {:game, 0, :init, %{}})
      {^mod, state} = Transcriber.maybe_record({mod, state}, {:game, 100, :tick})
      {^mod, state} = Transcriber.maybe_record({mod, state}, {:user, 200, :shift, :left})

      assert length(state.events) == 3
      assert Enum.at(state.events, 0) == {:game, 0, :init, %{}}
      assert Enum.at(state.events, 1) == {:game, 100, :tick}
      assert Enum.at(state.events, 2) == {:user, 200, :shift, :left}
    end
  end

  describe "maybe_finalize/1" do
    test "returns :ok when transcriber is nil" do
      assert Transcriber.maybe_finalize(nil) == :ok
    end

    test "calls finalize on the module" do
      Process.register(self(), :transcriber_test)
      {:ok, state} = TestTranscriber.init([])
      {mod, state} = Transcriber.maybe_record({TestTranscriber, state}, {:game, 0, :tick})

      assert :ok = Transcriber.maybe_finalize({mod, state})
      assert_receive {:finalized, finalized_state}
      assert finalized_state.events == [{:game, 0, :tick}]
    end
  end
end
