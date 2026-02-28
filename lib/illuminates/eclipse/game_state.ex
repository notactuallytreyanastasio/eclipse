defmodule Illuminates.Eclipse.GameState do
  @moduledoc """
  Top-level game state struct. All game data in one serializable structure.
  """

  alias Illuminates.Eclipse.Board
  alias Illuminates.Eclipse.Piece
  alias Illuminates.Eclipse.Scanner

  @type phase :: :waiting | :playing | :game_over
  @type t :: %__MODULE__{
          board: Board.t(),
          active_piece: Piece.t() | nil,
          queue: [Piece.t()],
          scanner: Scanner.t(),
          score: non_neg_integer(),
          level: non_neg_integer(),
          lines_cleared: non_neg_integer(),
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
            lines_cleared: 0,
            phase: :waiting,
            gravity_interval: 1000,
            scanner_interval: 50

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    board = Keyword.get(opts, :board, Board.new())

    %__MODULE__{
      board: board,
      scanner: Scanner.new(),
      queue: for(_ <- 1..3, do: Piece.random()),
      phase: :waiting,
      gravity_interval: Keyword.get(opts, :gravity_interval, 1000),
      scanner_interval: Keyword.get(opts, :scanner_interval, 50)
    }
  end
end
