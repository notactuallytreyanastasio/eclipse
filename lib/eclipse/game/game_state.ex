defmodule Eclipse.Game.GameState do
  @moduledoc """
  Top-level game state struct. All game data in one serializable structure.
  """

  alias Eclipse.Game.Board
  alias Eclipse.Game.Piece
  alias Eclipse.Game.Scanner

  @type phase :: :waiting | :playing | :game_over
  @type t :: %__MODULE__{
          board: Board.t(),
          active_piece: Piece.t() | nil,
          queue: [Piece.t()],
          scanner: Scanner.t(),
          score: non_neg_integer(),
          level: non_neg_integer(),
          total_squares_cleared: non_neg_integer(),
          combo_multiplier: pos_integer(),
          combo_streak: non_neg_integer(),
          sweep_cleared: non_neg_integer(),
          phase: phase(),
          gravity_interval: pos_integer(),
          scanner_interval: pos_integer()
        }

  defstruct board: nil,
            active_piece: nil,
            queue: [],
            scanner: nil,
            score: 0,
            level: 1,
            total_squares_cleared: 0,
            combo_multiplier: 1,
            combo_streak: 0,
            sweep_cleared: 0,
            phase: :waiting,
            gravity_interval: 1000,
            scanner_interval: 50

  @doc """
  Create a new game state with default or custom options.
  Prefer using the struct directly when you control all fields.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      board: Keyword.get(opts, :board, Board.new()),
      scanner: %Scanner{},
      queue: [Piece.random(), Piece.random(), Piece.random()],
      phase: :waiting,
      gravity_interval: Keyword.get(opts, :gravity_interval, 1000),
      scanner_interval: Keyword.get(opts, :scanner_interval, 50)
    }
  end
end
