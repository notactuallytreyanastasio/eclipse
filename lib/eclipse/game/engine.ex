defmodule Eclipse.Game.Engine do
  @moduledoc """
  Pure game logic engine. All functions take GameState in and return GameState out.
  No side effects, no timers, no processes.
  """

  alias Eclipse.Game.Board
  alias Eclipse.Game.GameState
  alias Eclipse.Game.Piece
  alias Eclipse.Game.Scanner

  @spec new_game(keyword()) :: GameState.t()
  def new_game(opts \\ []) do
    state = GameState.new(opts)
    {piece, queue} = pop_queue(state.queue)
    %{state | active_piece: piece, queue: queue}
  end

  @spec start(GameState.t()) :: GameState.t()
  def start(%GameState{} = state) do
    %{state | phase: :playing}
  end

  # --- Player Input ---

  @spec move_left(GameState.t()) :: GameState.t()
  def move_left(%GameState{phase: :playing, active_piece: piece} = state)
      when not is_nil(piece) do
    try_move(state, Piece.move(piece, :left))
  end

  def move_left(state), do: state

  @spec move_right(GameState.t()) :: GameState.t()
  def move_right(%GameState{phase: :playing, active_piece: piece} = state)
      when not is_nil(piece) do
    try_move(state, Piece.move(piece, :right))
  end

  def move_right(state), do: state

  @spec rotate_cw(GameState.t()) :: GameState.t()
  def rotate_cw(%GameState{phase: :playing, active_piece: piece} = state)
      when not is_nil(piece) do
    try_move(state, Piece.rotate_cw(piece))
  end

  def rotate_cw(state), do: state

  @spec rotate_ccw(GameState.t()) :: GameState.t()
  def rotate_ccw(%GameState{phase: :playing, active_piece: piece} = state)
      when not is_nil(piece) do
    try_move(state, Piece.rotate_ccw(piece))
  end

  def rotate_ccw(state), do: state

  @spec soft_drop(GameState.t()) :: GameState.t()
  def soft_drop(%GameState{phase: :playing, active_piece: piece} = state)
      when not is_nil(piece) do
    drop_one_row(state)
  end

  def soft_drop(state), do: state

  @spec hard_drop(GameState.t()) :: GameState.t()
  def hard_drop(%GameState{phase: :playing, active_piece: piece} = state)
      when not is_nil(piece) do
    dropped = drop_to_bottom(state.board, piece)
    lock_piece(%{state | active_piece: dropped})
  end

  def hard_drop(state), do: state

  # --- Tick Handlers ---

  @spec gravity_tick(GameState.t()) :: GameState.t()
  def gravity_tick(%GameState{phase: :playing, active_piece: piece} = state)
      when not is_nil(piece) do
    drop_one_row(state)
  end

  def gravity_tick(state), do: state

  @spec scanner_tick(GameState.t()) :: GameState.t()
  def scanner_tick(%GameState{phase: :playing, scanner: scanner, board: board} = state) do
    {new_scanner, from_col, to_col, wrapped?} = Scanner.advance(scanner, board.width)

    if from_col >= 0 and to_col >= 0 do
      {settled_board, cleared_count} = clear_and_settle(board, from_col, to_col, state)

      score_bonus = cleared_count * 10 * state.combo_multiplier

      # Apply bonuses
      score_bonus =
        cond do
          Board.empty?(settled_board) ->
            score_bonus + 10_000

          Board.single_color?(settled_board) ->
            score_bonus + 1_000

          true ->
            score_bonus
        end

      %{
        state
        | board: settled_board,
          scanner: new_scanner,
          score: state.score + score_bonus,
          total_squares_cleared: state.total_squares_cleared + cleared_count,
          sweep_cleared: state.sweep_cleared + cleared_count
      }
      |> evaluate_combo(wrapped?)
      |> maybe_level_up()
    else
      %{state | scanner: new_scanner}
    end
  end

  def scanner_tick(state), do: state

  defp clear_and_settle(board, from_col, to_col, _state) do
    board
    |> Board.clear_marked_in_range(from_col, to_col)
    |> settle_after_clear()
  end

  defp settle_after_clear({cleared_board, cleared_count}) do
    settled_board =
      cleared_board
      |> Board.apply_gravity()
      |> Board.find_matches()

    {settled_board, cleared_count}
  end

  defp evaluate_combo(%{sweep_cleared: cleared} = state, true) when cleared >= 4 do
    new_streak = state.combo_streak + 1
    new_multiplier = min(4, new_streak + 1)
    %{state | combo_streak: new_streak, combo_multiplier: new_multiplier, sweep_cleared: 0}
  end

  defp evaluate_combo(state, true) do
    %{state | combo_streak: 0, combo_multiplier: 1, sweep_cleared: 0}
  end

  defp evaluate_combo(state, false), do: state

  # --- Internal ---

  defp drop_one_row(%GameState{active_piece: piece, board: board} = state) do
    moved = Piece.move(piece, :down)

    if Board.any_collision?(board, moved) do
      lock_piece(state)
    else
      %{state | active_piece: moved}
    end
  end

  defp try_move(state, new_piece) do
    if Board.any_collision?(state.board, new_piece) do
      state
    else
      %{state | active_piece: new_piece}
    end
  end

  defp lock_piece(%GameState{active_piece: piece, board: board} = state) do
    new_board =
      board
      |> Board.place_piece(piece)
      |> Board.apply_gravity()
      |> Board.find_matches()

    if Board.topped_out?(new_board) do
      %{state | board: new_board, active_piece: nil, phase: :game_over}
    else
      {next_piece, new_queue} = pop_queue(state.queue)
      %{state | board: new_board, active_piece: next_piece, queue: new_queue}
    end
  end

  defp pop_queue([next | rest]) do
    {next, rest ++ [Piece.random()]}
  end

  defp drop_to_bottom(board, piece) do
    moved = Piece.move(piece, :down)

    if Board.any_collision?(board, moved) do
      piece
    else
      drop_to_bottom(board, moved)
    end
  end

  defp maybe_level_up(%GameState{total_squares_cleared: cleared, level: level} = state) do
    new_level = div(cleared, 50) + 1

    if new_level > level do
      new_interval = max(100, 1000 - (new_level - 1) * 100)
      %{state | level: new_level, gravity_interval: new_interval}
    else
      state
    end
  end
end
