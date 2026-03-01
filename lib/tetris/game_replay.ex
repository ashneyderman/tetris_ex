defmodule Tetris.GameReplay do
  @moduledoc """
  GenServer that replays a recorded transcript file, driving a renderer with
  proper timing. Unlike GameInstance, GameReplay does not accept external API
  inputs — it autonomously walks through the recorded events.
  """
  use GenServer

  alias Tetris.Core.Field
  alias Tetris.Core.Shape
  alias Tetris.Core.ShapeRepository

  defstruct field: nil,
            current_shape: nil,
            current_shape_coords: {0, 0},
            status: :live,
            score: 0,
            rows_cleared: 0,
            renderer: nil,
            events: [],
            speed: 1.0,
            timer_ref: nil,
            last_offset: 0

  def start_link(opts) do
    game_id = Keyword.get(opts, :game_id, 0)
    GenServer.start_link(__MODULE__, opts, name: :"replay_#{game_id}")
  end

  # --- Callbacks ---

  @impl true
  def init(opts) do
    path = Keyword.fetch!(opts, :path)
    renderer = Keyword.get(opts, :renderer, nil)
    speed = Keyword.get(opts, :speed, 1.0)

    events = read_transcript(path)

    state = %__MODULE__{
      renderer: renderer,
      speed: speed,
      events: events
    }

    {:ok, state, {:continue, :start_replay}}
  end

  @impl true
  def handle_continue(:start_replay, %__MODULE__{events: [first | rest]} = state) do
    state = apply_event(first, %{state | events: rest, last_offset: event_offset(first)})
    state = schedule_next(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:next_event, %__MODULE__{events: []} = state) do
    {:stop, :normal, %{state | timer_ref: nil}}
  end

  def handle_info(:next_event, %__MODULE__{events: [event | rest]} = state) do
    state = apply_event(event, %{state | events: rest, last_offset: event_offset(event)})
    maybe_render(state)

    if state.status == :over do
      {:stop, :normal, %{state | timer_ref: nil}}
    else
      state = schedule_next(state)
      {:noreply, state}
    end
  end

  # --- Event processing ---

  defp apply_event({:game, _offset, :init, %{width: w, height: h}}, state) do
    {:ok, field} = Field.new(w, h)
    %{state | field: field}
  end

  defp apply_event({:game, _offset, :new, label, {x, y}}, state) do
    {:ok, shape} = ShapeRepository.fetch_by_label(label)
    %{state | current_shape: shape, current_shape_coords: {x, y}}
  end

  defp apply_event({:game, _offset, :tick}, state) do
    {x, y} = state.current_shape_coords
    new_y = y + 1

    if Field.can_place?(state.field, state.current_shape, x, new_y) do
      %{state | current_shape_coords: {x, new_y}}
    else
      state
    end
  end

  defp apply_event({:user, _offset, :shift, direction}, state) do
    {x, y} = state.current_shape_coords
    delta = if direction == :left, do: -1, else: 1
    %{state | current_shape_coords: {x + delta, y}}
  end

  defp apply_event({:user, _offset, :rotate, direction}, state) do
    rotated = Shape.rotate(state.current_shape, direction)
    %{state | current_shape: rotated}
  end

  defp apply_event({:user, _offset, :drop_shape}, state) do
    {x, y} = state.current_shape_coords
    final_y = drop_to_bottom(state.field, state.current_shape, x, y)
    %{state | current_shape_coords: {x, final_y}}
  end

  defp apply_event({:game, _offset, :capture_shape}, state) do
    {x, y} = state.current_shape_coords
    {cleared, new_field} = Field.capture(state.field, state.current_shape, x, y)

    %{state |
      field: new_field,
      score: state.score + cleared * cleared,
      rows_cleared: state.rows_cleared + cleared
    }
  end

  defp apply_event({:game, _offset, :game_over}, state) do
    %{state | status: :over}
  end

  # --- Private helpers ---

  defp read_transcript(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      {term, _bindings} = Code.eval_string(line)
      term
    end)
  end

  defp drop_to_bottom(field, shape, x, y) do
    new_y = y + 1

    if Field.can_place?(field, shape, x, new_y) do
      drop_to_bottom(field, shape, x, new_y)
    else
      y
    end
  end

  defp schedule_next(%__MODULE__{events: []} = state) do
    ref = Process.send_after(self(), :next_event, 0)
    %{state | timer_ref: ref}
  end

  defp schedule_next(%__MODULE__{events: [next | _], last_offset: last, speed: speed} = state) do
    next_offset = event_offset(next)
    delay = max(round((next_offset - last) / speed), 0)
    ref = Process.send_after(self(), :next_event, delay)
    %{state | timer_ref: ref}
  end

  defp event_offset(event), do: elem(event, 1)

  defp maybe_render(%__MODULE__{renderer: renderer} = state) do
    Tetris.Renderer.maybe_render(renderer, %{
      field: state.field,
      current_shape: state.current_shape,
      current_shape_coords: state.current_shape_coords,
      score: state.score,
      rows_cleared: state.rows_cleared,
      status: state.status
    })
  end
end
