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
    {new_scanner, from_col, to_col} = Scanner.advance(scanner, board.width)

    if from_col >= 0 and to_col >= 0 do
      {cleared_board, cleared_count} = Board.clear_marked_in_range(board, from_col, to_col)

      settled_board =
        cleared_board
        |> Board.apply_gravity()
        |> Board.find_matches()

      score_bonus = cleared_count * 10 * state.level

      %{
        state
        | board: settled_board,
          scanner: new_scanner,
          score: state.score + score_bonus,
          lines_cleared: state.lines_cleared + cleared_count
      }
      |> maybe_level_up()
    else
      %{state | scanner: new_scanner}
    end
  end

  def scanner_tick(state), do: state

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
      |> Board.find_matches()

    if Board.topped_out?(new_board) do
      %{state | board: new_board, active_piece: nil, phase: :game_over}
    else
      {next_piece, new_queue} = pop_queue(state.queue)
      %{state | board: new_board, active_piece: next_piece, queue: new_queue}
    end
  end

  defp pop_queue(queue) do
    [next | rest] = queue
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

  defp maybe_level_up(%GameState{lines_cleared: cleared, level: level} = state) do
    new_level = div(cleared, 50) + 1

    if new_level > level do
      new_interval = max(100, 1000 - (new_level - 1) * 100)
      %{state | level: new_level, gravity_interval: new_interval}
    else
      state
    end
  end
end
