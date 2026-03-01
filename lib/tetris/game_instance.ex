defmodule Tetris.GameInstance do
  @moduledoc """
  Game gen_server that keeps track of game instance state - current field, shape and
  shape's coordinates as it is falling inside the field. It also processes commands
  that are issued by the system such as `tick` or by user action such as key press
  that causes shape rotation or the shape drop to the bottom of the field.

  Example usage:
    iex> Tetris.GameInstance.start_link(
           width: 15,
           height: 35,
           tick_time: 100,
           renderer: Tetris.Renderer.Console,
           transcriber: {Tetris.Transcriber.File, path: "/tmp/my_game_transcript1.txt"}
         )
  """
  use GenServer

  alias Tetris.Core.Field
  alias Tetris.Core.Shape
  alias Tetris.Core.ShapeRepository
  alias Tetris.Transcriber

  defstruct field: nil,
            current_shape: nil,
            current_shape_coords: {0, 0},
            status: :paused,
            tick_time: 1000,
            tick_ref: nil,
            score: 0,
            rows_cleared: 0,
            renderer: nil,
            transcriber: nil,
            start_time: nil,
            shape_provider: nil

  def start_link(opts) do
    game_id = Keyword.get(opts, :game_id, 0)
    GenServer.start_link(__MODULE__, opts, name: :"game_#{game_id}")
  end

  def rotate(pid_or_name, direction) when direction in [:cw, :ccw] do
    GenServer.call(pid_or_name, {:rotate, direction})
  end

  def shift(pid_or_name, direction) when direction in [:left, :right] do
    GenServer.call(pid_or_name, {:shift, direction})
  end

  def drop_shape(pid_or_name) do
    GenServer.call(pid_or_name, :drop_shape)
  end

  def pause(pid_or_name) do
    GenServer.call(pid_or_name, :pause)
  end

  def unpause(pid_or_name) do
    GenServer.call(pid_or_name, :unpause)
  end

  def status(pid_or_name) do
    GenServer.call(pid_or_name, :status)
  end

  # --- Callbacks ---

  @impl true
  def init(opts) do
    width = Keyword.get(opts, :width, 10)
    height = Keyword.get(opts, :height, 20)
    tick_time = Keyword.get(opts, :tick_time, 1000)
    renderer = Keyword.get(opts, :renderer, nil)
    shape_provider = Keyword.get(opts, :shape_provider, &ShapeRepository.select_random_shape/0)

    transcriber =
      case Keyword.get(opts, :transcriber, nil) do
        {mod, transcriber_opts} ->
          {:ok, state} = mod.init(transcriber_opts)
          {mod, state}

        nil ->
          nil
      end

    start_time = System.monotonic_time(:millisecond)

    {:ok, field} = Field.new(width, height)
    shape = shape_provider.()
    {x, y} = Field.starting_position(field, shape)

    state = %__MODULE__{
      field: field,
      current_shape: shape,
      current_shape_coords: {x, y},
      status: :paused,
      tick_time: tick_time,
      renderer: renderer,
      transcriber: transcriber,
      start_time: start_time,
      shape_provider: shape_provider
    }

    state =
      maybe_transcribe(
        state,
        {:game, :offset, :init, %{width: width, height: height, tick_time: tick_time}}
      )

    state = maybe_transcribe(state, {:game, :offset, :new, shape.label, {x, y}})

    {:ok, state, {:continue, :start_tick}}
  end

  @impl true
  def handle_continue(:start_tick, %__MODULE__{tick_time: tick_time} = state) do
    tick_ref = maybe_schedule_tick(tick_time)
    new_state = %{state | tick_ref: tick_ref, status: :live}
    maybe_render(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_call({:rotate, direction}, _from, state) when direction in [:cw, :ccw] do
    %__MODULE__{field: field, current_shape: shape, current_shape_coords: {x, y}} = state
    rotated = Shape.rotate(shape, direction)

    if Field.can_place?(field, rotated, x, y) do
      new_state = %{state | current_shape: rotated}
      new_state = maybe_transcribe(new_state, {:user, :offset, :rotate, direction})
      maybe_render(new_state)
      {:reply, {:ok, state}, new_state}
    else
      {:reply, {:error, :unable_to_rotate}, state}
    end
  end

  def handle_call({:shift, direction}, _from, state) when direction in [:left, :right] do
    %__MODULE__{field: field, current_shape: shape, current_shape_coords: {x, y}} = state
    delta_x = if direction == :left, do: -1, else: 1
    new_x = x + delta_x

    if Field.can_place?(field, shape, new_x, y) do
      new_state = %{state | current_shape_coords: {new_x, y}}
      new_state = maybe_transcribe(new_state, {:user, :offset, :shift, direction})
      maybe_render(new_state)
      {:reply, {:ok, new_state}, new_state}
    else
      {:reply, {:error, :unable_to_shift}, state}
    end
  end

  def handle_call(:drop_shape, _from, %__MODULE__{status: :over} = state) do
    {:reply, {:error, :game_over}, state}
  end

  def handle_call(:drop_shape, _from, %__MODULE__{status: :paused} = state) do
    {:reply, {:error, :paused}, state}
  end

  def handle_call(:drop_shape, _from, %__MODULE__{status: :live} = state) do
    %__MODULE__{
      field: field,
      current_shape: shape,
      current_shape_coords: {x, y},
      tick_time: tick_time,
      tick_ref: tick_ref,
      shape_provider: shape_provider
    } = state

    # 1. Stop the current tick timer
    if tick_ref, do: Process.cancel_timer(tick_ref)

    # 2. Find the lowest valid y by progressively increasing y
    final_y = drop_to_bottom(field, shape, x, y)

    state = maybe_transcribe(state, {:user, :offset, :drop_shape})

    # 3. Check for game over
    if game_over?(shape, x, final_y) do
      state = maybe_transcribe(state, {:game, :offset, :game_over})
      new_state = %{state | status: :over, tick_ref: nil}
      maybe_render(new_state)
      {:reply, :ok, new_state}
    else
      {cleared, new_field} = Field.capture(field, shape, x, final_y)
      state = maybe_transcribe(state, {:game, :offset, :capture_shape})

      new_shape = shape_provider.()
      {new_x, new_y} = Field.starting_position(new_field, new_shape)
      state = maybe_transcribe(state, {:game, :offset, :new, new_shape.label, {new_x, new_y}})

      new_tick_ref = maybe_schedule_tick(tick_time)

      new_state =
        %{
          state
          | field: new_field,
            current_shape: new_shape,
            current_shape_coords: {new_x, new_y},
            tick_ref: new_tick_ref,
            score: state.score + cleared * cleared,
            rows_cleared: state.rows_cleared + cleared
        }

      maybe_render(new_state)
      {:reply, :ok, new_state}
    end
  end

  def handle_call(:pause, _from, %__MODULE__{status: :over} = state) do
    {:reply, {:error, :game_over}, state}
  end

  def handle_call(:pause, _from, %__MODULE__{status: :live, tick_ref: tick_ref} = state) do
    if tick_ref, do: Process.cancel_timer(tick_ref)
    new_state = %{state | status: :paused, tick_ref: nil}
    maybe_render(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call(:pause, _from, %__MODULE__{status: :paused} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:unpause, _from, %__MODULE__{status: :over} = state) do
    {:reply, {:error, :game_over}, state}
  end

  def handle_call(:unpause, _from, %__MODULE__{status: :paused, tick_time: tick_time} = state) do
    tick_ref = maybe_schedule_tick(tick_time)
    new_state = %{state | status: :live, tick_ref: tick_ref}
    maybe_render(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call(:unpause, _from, %__MODULE__{status: :live} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:status, _from, %__MODULE__{status: status} = state) do
    {:reply, status, state}
  end

  @impl true
  def handle_info(:tick, %__MODULE__{} = state) do
    %__MODULE__{
      field: field,
      current_shape: shape,
      current_shape_coords: {x, y},
      tick_time: tick_time,
      shape_provider: shape_provider
    } = state

    new_y = y + 1

    state = maybe_transcribe(state, {:game, :offset, :tick})

    if Field.can_place?(field, shape, x, new_y) do
      tick_ref = maybe_schedule_tick(tick_time)
      new_state = %{state | current_shape_coords: {x, new_y}, tick_ref: tick_ref}
      maybe_render(new_state)
      {:noreply, new_state}
    else
      if game_over?(shape, x, y) do
        state = maybe_transcribe(state, {:game, :offset, :game_over})
        new_state = %{state | status: :over, tick_ref: nil}
        maybe_render(new_state)
        {:noreply, new_state}
      else
        {cleared, new_field} = Field.capture(field, shape, x, y)
        state = maybe_transcribe(state, {:game, :offset, :capture_shape})

        new_shape = shape_provider.()
        {new_x, new_y} = Field.starting_position(new_field, new_shape)
        state = maybe_transcribe(state, {:game, :offset, :new, new_shape.label, {new_x, new_y}})

        tick_ref = maybe_schedule_tick(tick_time)

        new_state =
          %{
            state
            | field: new_field,
              current_shape: new_shape,
              current_shape_coords: {new_x, new_y},
              tick_ref: tick_ref,
              score: state.score + cleared * cleared,
              rows_cleared: state.rows_cleared + cleared
          }

        maybe_render(new_state)
        {:noreply, new_state}
      end
    end
  end

  @impl true
  def terminate(_reason, %__MODULE__{transcriber: transcriber}) do
    Transcriber.maybe_finalize(transcriber)
  end

  defp drop_to_bottom(field, shape, x, y) do
    new_y = y + 1

    if Field.can_place?(field, shape, x, new_y) do
      drop_to_bottom(field, shape, x, new_y)
    else
      y
    end
  end

  defp game_over?(%Shape{coords: coords}, _offset_x, offset_y) do
    Enum.any?(coords, fn [_x, y] -> round(y + offset_y + 0.1) <= 0 end)
  end

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

  defp maybe_transcribe(%__MODULE__{transcriber: nil} = state, _event), do: state

  defp maybe_transcribe(
         %__MODULE__{transcriber: transcriber, start_time: start_time} = state,
         event
       ) do
    event = put_time_offset(event, start_time)
    %{state | transcriber: Transcriber.maybe_record(transcriber, event)}
  end

  defp put_time_offset(event, start_time) do
    offset = System.monotonic_time(:millisecond) - start_time
    put_elem(event, 1, offset)
  end

  defp maybe_schedule_tick(:infinity), do: nil
  defp maybe_schedule_tick(ms), do: Process.send_after(self(), :tick, ms)
end
