defmodule Tetris.Renderer do
  @moduledoc """
  Behaviour for rendering Tetris game state.

  Implementations receive a map of render data and produce visual output
  (terminal, GUI, etc).
  """

  @type render_data :: %{
          field: Tetris.Core.Field.t(),
          current_shape: Tetris.Core.Shape.t(),
          current_shape_coords: {number(), number()},
          score: non_neg_integer(),
          rows_cleared: non_neg_integer(),
          status: :live | :paused | :over
        }

  @callback render(render_data()) :: :ok

  @doc """
  Calls `renderer.render(data)` when a renderer is configured, no-ops otherwise.
  """
  @spec maybe_render(module() | nil, render_data()) :: :ok
  def maybe_render(nil, _data), do: :ok
  def maybe_render(renderer, data), do: renderer.render(data)
end
