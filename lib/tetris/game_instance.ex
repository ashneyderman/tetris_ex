defmodule Tetris.GameInstance do
  @moduledoc """
  Game gen_server that keeps track of game instance state - current field, shape and
  shape's coordinates as it is falling inside the field. It also processes commands
  that are issued by the system such as `tick` or by user action such as key press
  that causes shape rotation or the shape drop to the bottom of the field.
  """
  use GenServer

  def start_link(opts) do
    game_id = Keyword.get(opts, :game_id, 0)
    GenServer.start_link(__MODULE__, opts, name: :"game_#{game_id}")
  end

  def init(opts) do
    IO.inspect(opts, label: "Tetris.GameInstance init opts")
    {:ok, %{}}
  end

  def handle_call(:start, state) do
    {:reply, :ok, state}
  end

  def handle_call(:stop, state) do
    {:reply, :ok, state}
  end

  def handle_call({:rorate, :cw}, state) do
    {:reply, :ok, state}
  end

  def handle_call({:rotate, :ccw}, state) do
    {:reply, :ok, state}
  end

  def handle_call(:drop_shape, state) do
    {:reply, :ok, state}
  end

  def handle_call(:pause, state) do
    {:reply, :ok, state}
  end

  def handle_info(:tick, state) do
    {:noreply, state}
  end
end
