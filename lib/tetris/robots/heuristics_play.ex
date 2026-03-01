defmodule Tetris.Robots.HeuristicsPlay do
  @moduledoc """
  An automated Tetris player that receives new-piece notifications from
  `GameInstance`, computes optimal placements using heuristic board evaluation,
  and executes moves via the public API, rate-limited by `moves_per_tick`.
  """
  use GenServer

  alias Tetris.Core.Field
  alias Tetris.Core.Shape
  alias Tetris.GameInstance

  defstruct game_pid: nil,
            moves_per_tick: 1,
            move_queue: [],
            tick_time: 1000,
            timer_ref: nil,
            duration_sec: nil,
            started_at: nil

  # --- Public API ---

  def start_link(opts) do
    game_pid = Keyword.fetch!(opts, :game_pid)
    moves_per_tick = Keyword.get(opts, :moves_per_tick, 3)
    duration_sec = Keyword.get(opts, :duration_sec, nil)

    GenServer.start_link(__MODULE__, %{
      game_pid: game_pid,
      moves_per_tick: moves_per_tick,
      duration_sec: duration_sec
    })
  end

  # --- Callbacks ---

  @impl true
  def init(%{game_pid: game_pid, moves_per_tick: moves_per_tick, duration_sec: duration_sec}) do
    {:ok,
     %__MODULE__{
       game_pid: game_pid,
       moves_per_tick: moves_per_tick,
       duration_sec: duration_sec,
       started_at: System.monotonic_time(:second)
     }}
  end

  @impl true
  def handle_cast({:new_piece, data}, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    if expired?(state) do
      {:noreply, %{state | move_queue: [], timer_ref: nil}}
    else
      %{field: field, shape: shape, shape_coords: {start_x, _start_y}, tick_time: tick_time} = data

      moves = compute_move_sequence(field, shape, start_x)

      new_state = %{state | move_queue: moves, tick_time: tick_time, timer_ref: nil}
      new_state = execute_batch(new_state)
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:execute_moves, state) do
    new_state = %{state | timer_ref: nil}
    new_state = execute_batch(new_state)
    {:noreply, new_state}
  end

  # --- Move Execution ---

  defp execute_batch(%__MODULE__{move_queue: []} = state), do: state

  defp execute_batch(%__MODULE__{} = state) do
    {batch, rest} = Enum.split(state.move_queue, state.moves_per_tick)

    remaining = execute_moves(state.game_pid, batch, rest)

    state = %{state | move_queue: remaining}

    if remaining != [] do
      ref = schedule_next_batch(state.tick_time)
      %{state | timer_ref: ref}
    else
      state
    end
  end

  defp execute_moves(_game_pid, [], rest), do: rest

  defp execute_moves(game_pid, [move | batch], rest) do
    result = execute_one(game_pid, move)

    case result do
      :ok -> execute_moves(game_pid, batch, rest)
      {:ok, _} -> execute_moves(game_pid, batch, rest)
      {:error, _} -> []
    end
  end

  defp execute_one(game_pid, move) do
    try do
      case move do
        :rotate_cw -> GameInstance.rotate(game_pid, :cw)
        :rotate_ccw -> GameInstance.rotate(game_pid, :ccw)
        :shift_left -> GameInstance.shift(game_pid, :left)
        :shift_right -> GameInstance.shift(game_pid, :right)
        :drop -> GameInstance.drop_shape(game_pid)
      end
    catch
      :exit, _ -> {:error, :game_exited}
    end
  end

  defp expired?(%__MODULE__{duration_sec: nil}), do: false

  defp expired?(%__MODULE__{duration_sec: duration_sec, started_at: started_at}) do
    System.monotonic_time(:second) - started_at >= duration_sec
  end

  defp schedule_next_batch(:infinity) do
    send(self(), :execute_moves)
    nil
  end

  defp schedule_next_batch(ms), do: Process.send_after(self(), :execute_moves, ms)

  # --- Placement Algorithm ---

  @doc false
  def compute_move_sequence(field, shape, start_x) do
    case enumerate_placements(field, shape) do
      [] ->
        [:drop]

      placements ->
        {best_rotations, best_x, _score} =
          placements
          |> Enum.max_by(fn {_rotations, _x, score} -> score end)

        build_moves(best_rotations, start_x, best_x)
    end
  end

  @doc false
  def enumerate_placements(field, shape) do
    rotations = unique_rotations(shape)

    Enum.flat_map(rotations, fn {rotated_shape, num_rotations} ->
      {min_x, max_x} = x_range(field, rotated_shape)

      for x <- min_x..max_x,
          Field.can_place?(field, rotated_shape, x, 0) or placeable_anywhere?(field, rotated_shape, x) do
        final_y = drop_to_bottom(field, rotated_shape, x, -4)
        {cleared, new_field} = Field.capture(field, rotated_shape, x, final_y)
        score = evaluate_board(new_field, cleared)
        {num_rotations, x, score}
      end
    end)
  end

  defp placeable_anywhere?(field, shape, x) do
    Enum.any?(-4..0, fn y -> Field.can_place?(field, shape, x, y) end)
  end

  @doc false
  def evaluate_board(%Field{} = field, cleared) do
    heights = column_heights(field)
    agg = Enum.sum(heights)
    holes = count_holes(field)
    bump = bumpiness(heights)

    -0.510066 * agg + 0.760666 * cleared - 0.35663 * holes - 0.184483 * bump
  end

  @doc false
  def build_moves(num_rotations, start_x, target_x) do
    rotations = List.duplicate(:rotate_cw, num_rotations)

    shift_count = target_x - start_x

    shifts =
      cond do
        shift_count > 0 -> List.duplicate(:shift_right, shift_count)
        shift_count < 0 -> List.duplicate(:shift_left, abs(shift_count))
        true -> []
      end

    rotations ++ shifts ++ [:drop]
  end

  # --- Board Metrics ---

  defp column_heights(%Field{cells: cells, width: width, height: height}) do
    for col <- 0..(width - 1) do
      column_height(cells, col, height)
    end
  end

  defp column_height(cells, col, height) do
    row_idx =
      Enum.find_index(0..(height - 1), fn row ->
        Enum.at(Enum.at(cells, row), col) == 1
      end)

    case row_idx do
      nil -> 0
      idx -> height - idx
    end
  end

  defp count_holes(%Field{cells: cells, width: width, height: height}) do
    for col <- 0..(width - 1), reduce: 0 do
      acc ->
        h = column_height(cells, col, height)
        top_row = height - h

        holes_in_col =
          if h == 0 do
            0
          else
            Enum.count((top_row + 1)..(height - 1)//1, fn row ->
              Enum.at(Enum.at(cells, row), col) == 0
            end)
          end

        acc + holes_in_col
    end
  end

  defp bumpiness(heights) do
    heights
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> abs(a - b) end)
    |> Enum.sum()
  end

  # --- Shape Helpers ---

  @doc false
  def unique_rotations(shape) do
    all =
      Enum.reduce(0..3, [{shape, 0}], fn i, acc ->
        if i == 0 do
          acc
        else
          {prev_shape, _} = List.last(acc)
          rotated = Shape.rotate(prev_shape, :cw)
          acc ++ [{rotated, i}]
        end
      end)

    Enum.uniq_by(all, fn {s, _n} -> normalize_coords(s) end)
  end

  defp normalize_coords(%Shape{coords: coords}) do
    snapped = Enum.map(coords, fn [x, y] -> {round(x * 2), round(y * 2)} end)
    sorted = Enum.sort(snapped)

    case sorted do
      [{min_x, min_y} | _] ->
        Enum.map(sorted, fn {x, y} -> {x - min_x, y - min_y} end)

      [] ->
        []
    end
  end

  defp x_range(%Field{width: width}, %Shape{coords: coords}) do
    xs = Enum.map(coords, fn [x, _y] -> round(x + 0.1) end)
    min_shape_x = Enum.min(xs)
    max_shape_x = Enum.max(xs)

    {0 - min_shape_x, width - 1 - max_shape_x}
  end

  defp drop_to_bottom(field, shape, x, y) do
    new_y = y + 1

    if Field.can_place?(field, shape, x, new_y) do
      drop_to_bottom(field, shape, x, new_y)
    else
      y
    end
  end
end
