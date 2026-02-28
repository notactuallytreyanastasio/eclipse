defmodule Illuminates.Eclipse.Piece do
  @moduledoc """
  A 2x2 falling block composed of dark and light tiles.

  Cells are stored as a 4-element tuple in row-major order:
  {top_left, top_right, bottom_left, bottom_right}
  """

  @type color :: :dark | :light
  @type t :: %__MODULE__{
          cells: {color(), color(), color(), color()},
          col: non_neg_integer(),
          row: integer()
        }

  defstruct [:cells, col: 11, row: 0]

  @patterns [
    {:dark, :light, :light, :dark},
    {:light, :dark, :dark, :light},
    {:dark, :dark, :dark, :dark},
    {:light, :light, :light, :light},
    {:light, :light, :dark, :dark},
    {:dark, :dark, :light, :light}
  ]

  @spec patterns() :: [tuple()]
  def patterns, do: @patterns

  @spec random() :: t()
  def random do
    %__MODULE__{cells: Enum.random(@patterns), col: 11, row: 0}
  end

  @spec rotate_cw(t()) :: t()
  def rotate_cw(%__MODULE__{cells: {tl, tr, bl, br}} = piece) do
    %{piece | cells: {bl, tl, br, tr}}
  end

  @spec rotate_ccw(t()) :: t()
  def rotate_ccw(%__MODULE__{cells: {tl, tr, bl, br}} = piece) do
    %{piece | cells: {tr, br, tl, bl}}
  end

  @spec cells_positions(t()) :: [{non_neg_integer(), integer(), color()}]
  def cells_positions(%__MODULE__{cells: {tl, tr, bl, br}, col: col, row: row}) do
    [
      {col, row, tl},
      {col + 1, row, tr},
      {col, row + 1, bl},
      {col + 1, row + 1, br}
    ]
  end

  @spec move(t(), :left | :right | :down) :: t()
  def move(piece, :left), do: %{piece | col: piece.col - 1}
  def move(piece, :right), do: %{piece | col: piece.col + 1}
  def move(piece, :down), do: %{piece | row: piece.row + 1}
end
