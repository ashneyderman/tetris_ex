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

  def handle_call(:drop_shape, _from, state) do
    {:reply, :ok, state}
  end

  def handle_call(:pause, _from, state) do
    {:reply, :ok, state}
  end

  def handle_call(:unpause, _from, state) do
    {:reply, :ok, state}
  end

  def handle_call(:status, _from, %__MODULE__{status: status} = state) do
    {:reply, status, state}
  end

  @impl true
  def handle_info(:tick, state) do
    {:noreply, state}
  end
end
