defmodule Tetris.RendererTest do
  use ExUnit.Case

  alias Tetris.Renderer

  defmodule MockRenderer do
    @behaviour Tetris.Renderer

    @impl true
    def render(data) do
      send(Process.whereis(:renderer_test), {:rendered, data})
      :ok
    end
  end

  setup do
    Process.register(self(), :renderer_test)
    :ok
  end

  defp sample_render_data do
    {:ok, field} = Tetris.Core.Field.new(4, 4)

    %{
      field: field,
      current_shape: %Tetris.Core.Shape{label: :dot, coords: [[0, 0]]},
      current_shape_coords: {1, 1},
      score: 42,
      rows_cleared: 3,
      status: :live
    }
  end

  describe "maybe_render/2" do
    test "returns :ok and does nothing when renderer is nil" do
      assert :ok = Renderer.maybe_render(nil, sample_render_data())
      refute_received {:rendered, _}
    end

    test "delegates to renderer module when present" do
      data = sample_render_data()
      assert :ok = Renderer.maybe_render(MockRenderer, data)
      assert_received {:rendered, ^data}
    end
  end
end
