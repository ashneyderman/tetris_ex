defmodule Tetris.GameInstance do
  @moduledoc """
  Game gen_server that keeps track of game instance state - current field, shape and
  shape's coordinates as it is falling inside the field. It also processes commands
  that are issued by the system such as `tick` or by user action such as key press
  that causes shape rotation or the shape drop to the bottom of the field.
  """
  use GenServer

  alias Tetris.Core.Field
  alias Tetris.Core.Shape
  alias Tetris.Core.ShapeRepository

  defstruct field: nil,
            current_shape: nil,
            current_shape_coords: {0, 0},
            status: :paused,
            tick_time: 1000,
            tick_ref: nil

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

    {:ok, field} = Field.new(width, height)
    shape = ShapeRepository.select_random_shape()
    {x, y} = Field.starting_position(field, shape)

    state = %__MODULE__{
      field: field,
      current_shape: shape,
      current_shape_coords: {x, y},
      status: :paused,
      tick_time: tick_time
    }

    {:ok, state, {:continue, :start_tick}}
  end

  @impl true
  def handle_continue(:start_tick, %__MODULE__{tick_time: tick_time} = state) do
    tick_ref = Process.send_after(self(), :tick, tick_time)
    {:noreply, %{state | tick_ref: tick_ref, status: :live}}
  end

  @impl true
  def handle_call({:rotate, direction}, _from, state) when direction in [:cw, :ccw] do
    %__MODULE__{field: field, current_shape: shape, current_shape_coords: {x, y}} = state
    rotated = Shape.rotate(shape, direction)

    if Field.can_place?(field, rotated, x, y) do
      {:reply, {:ok, state}, %{state | current_shape: rotated}}
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
      tick_ref: tick_ref
    } = state

    # 1. Stop the current tick timer
    if tick_ref, do: Process.cancel_timer(tick_ref)

    # 2. Find the lowest valid y by progressively increasing y
    final_y = drop_to_bottom(field, shape, x, y)

    # 3. Check for game over
    if game_over?(shape, x, final_y) do
      {:reply, :ok, %{state | status: :over, tick_ref: nil}}
    else
      {_rows_cleared, new_field} = Field.capture(field, shape, x, final_y)
      new_shape = ShapeRepository.select_random_shape()
      {new_x, new_y} = Field.starting_position(new_field, new_shape)
      new_tick_ref = Process.send_after(self(), :tick, tick_time)

      {:reply, :ok,
       %{state |
         field: new_field,
         current_shape: new_shape,
         current_shape_coords: {new_x, new_y},
         tick_ref: new_tick_ref
       }}
    end
  end

  def handle_call(:pause, _from, %__MODULE__{status: :over} = state) do
    {:reply, {:error, :game_over}, state}
  end

  def handle_call(:pause, _from, %__MODULE__{status: :live, tick_ref: tick_ref} = state) do
    if tick_ref, do: Process.cancel_timer(tick_ref)
    {:reply, :ok, %{state | status: :paused, tick_ref: nil}}
  end

  def handle_call(:pause, _from, %__MODULE__{status: :paused} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:unpause, _from, %__MODULE__{status: :over} = state) do
    {:reply, {:error, :game_over}, state}
  end

  def handle_call(:unpause, _from, %__MODULE__{status: :paused, tick_time: tick_time} = state) do
    tick_ref = Process.send_after(self(), :tick, tick_time)
    {:reply, :ok, %{state | status: :live, tick_ref: tick_ref}}
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
      tick_time: tick_time
    } = state

    new_y = y + 1

    if Field.can_place?(field, shape, x, new_y) do
      tick_ref = Process.send_after(self(), :tick, tick_time)
      {:noreply, %{state | current_shape_coords: {x, new_y}, tick_ref: tick_ref}}
    else
      if game_over?(shape, x, y) do
        {:noreply, %{state | status: :over, tick_ref: nil}}
      else
        {_rows_cleared, new_field} = Field.capture(field, shape, x, y)
        new_shape = ShapeRepository.select_random_shape()
        {new_x, new_y} = Field.starting_position(new_field, new_shape)
        tick_ref = Process.send_after(self(), :tick, tick_time)

        {:noreply,
         %{state |
           field: new_field,
           current_shape: new_shape,
           current_shape_coords: {new_x, new_y},
           tick_ref: tick_ref
         }}
      end
    end
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
end
