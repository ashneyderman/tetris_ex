defmodule Tetris.GameReplay do
  @moduledoc """
  GenServer that replays a recorded transcript, driving a renderer with
  proper timing. Unlike GameInstance, GameReplay does not accept external API
  inputs — it autonomously walks through the recorded events.

  Events are consumed lazily from a stream provided by a transcriber module.

  Example usage:
    iex> Tetris.GameReplay.start_link(
           renderer: Tetris.Renderer.Console,
           transcriber: {Tetris.Transcriber.File, path: "/tmp/my_game_transcript1.txt"}
         )
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
            next_event: nil,
            stream_cont: nil,
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
    {mod, transcriber_opts} = Keyword.fetch!(opts, :transcriber)
    renderer = Keyword.get(opts, :renderer, nil)
    speed = Keyword.get(opts, :speed, 1.0)

    stream = mod.stream(transcriber_opts)

    state = %__MODULE__{
      renderer: renderer,
      speed: speed
    }

    {:ok, state, {:continue, {:start_replay, stream}}}
  end

  @impl true
  def handle_continue({:start_replay, stream}, state) do
    case pull_event_from_stream(stream) do
      {:event, first, cont} ->
        state = apply_event(first, %{state | last_offset: event_offset(first)})

        case pull_event_from_cont(cont) do
          {:event, next, cont2} ->
            state = %{state | next_event: next, stream_cont: cont2}
            state = schedule_next(state)
            {:noreply, state}

          :done ->
            {:stop, :normal, %{state | next_event: :done, stream_cont: nil}}
        end

      :done ->
        {:stop, :normal, %{state | next_event: :done, stream_cont: nil}}
    end
  end

  @impl true
  def handle_info(:next_event, %__MODULE__{next_event: :done} = state) do
    {:stop, :normal, %{state | timer_ref: nil}}
  end

  def handle_info(:next_event, %__MODULE__{next_event: event, stream_cont: cont} = state) do
    state = apply_event(event, %{state | last_offset: event_offset(event)})
    maybe_render(state)

    if state.status == :over do
      halt_stream(cont)
      {:stop, :normal, %{state | timer_ref: nil, next_event: :done, stream_cont: nil}}
    else
      case pull_event_from_cont(cont) do
        {:event, next, cont2} ->
          state = %{state | next_event: next, stream_cont: cont2}
          state = schedule_next(state)
          {:noreply, state}

        :done ->
          {:stop, :normal, %{state | timer_ref: nil, next_event: :done, stream_cont: nil}}
      end
    end
  end

  @impl true
  def terminate(_reason, %__MODULE__{stream_cont: cont}) do
    halt_stream(cont)
    :ok
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

    %{
      state
      | field: new_field,
        score: state.score + cleared * cleared,
        rows_cleared: state.rows_cleared + cleared
    }
  end

  defp apply_event({:game, _offset, :game_over}, state) do
    %{state | status: :over}
  end

  # --- Stream helpers ---

  defp pull_event_from_stream(stream) do
    result =
      Enumerable.reduce(stream, {:cont, nil}, fn event, _acc ->
        {:suspend, event}
      end)

    case result do
      {:suspended, event, cont} -> {:event, event, cont}
      {:done, _acc} -> :done
      {:halted, _acc} -> :done
    end
  end

  defp pull_event_from_cont(cont) do
    case cont.({:cont, nil}) do
      {:suspended, event, cont2} -> {:event, event, cont2}
      {:done, _acc} -> :done
      {:halted, _acc} -> :done
    end
  end

  defp halt_stream(nil), do: :ok
  defp halt_stream(cont), do: cont.({:halt, nil})

  # --- Private helpers ---

  defp drop_to_bottom(field, shape, x, y) do
    new_y = y + 1

    if Field.can_place?(field, shape, x, new_y) do
      drop_to_bottom(field, shape, x, new_y)
    else
      y
    end
  end

  defp schedule_next(%__MODULE__{next_event: :done} = state) do
    ref = Process.send_after(self(), :next_event, 0)
    %{state | timer_ref: ref}
  end

  defp schedule_next(%__MODULE__{next_event: next, last_offset: last, speed: speed} = state) do
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
