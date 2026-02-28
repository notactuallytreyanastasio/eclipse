defmodule Eclipse.Game.Board do
  @moduledoc """
  A 24x10 game board stored as a map of {col, row} => cell.

  Cell values:
  - nil         - empty
  - :dark       - settled dark tile
  - :light      - settled light tile
  - {:marked, :dark}  - dark tile marked for scanner clearing
  - {:marked, :light} - light tile marked for scanner clearing
  """

  alias Eclipse.Game.Piece

  @type color :: :dark | :light
  @type cell :: nil | color() | {:marked, color()}
  @type t :: %__MODULE__{
          cells: %{optional({non_neg_integer(), non_neg_integer()}) => cell()},
          width: pos_integer(),
          height: pos_integer()
        }

  defstruct cells: %{}, width: 24, height: 10

  @doc """
  Create a new board with the given dimensions.

  This is a convenience function for tests and initialization.
  When you control all fields, prefer using the struct directly:
  `%Board{cells: %{}, width: 24, height: 10}`
  """
  @spec new(pos_integer(), pos_integer()) :: t()
  def new(width \\ 24, height \\ 10) do
    %__MODULE__{width: width, height: height}
  end

  @spec get(t(), non_neg_integer(), non_neg_integer()) :: cell()
  def get(%__MODULE__{cells: cells}, col, row) do
    Map.get(cells, {col, row})
  end

  @spec put(t(), non_neg_integer(), non_neg_integer(), cell()) :: t()
  def put(%__MODULE__{cells: cells} = board, col, row, value) do
    new_cells =
      if is_nil(value) do
        Map.delete(cells, {col, row})
      else
        Map.put(cells, {col, row}, value)
      end

    %{board | cells: new_cells}
  end

  @spec place_piece(t(), Piece.t()) :: t()
  def place_piece(board, piece) do
    Piece.cells_positions(piece)
    |> Enum.reduce(board, fn {col, row, color}, acc ->
      put(acc, col, row, color)
    end)
  end

  @spec any_collision?(t(), Piece.t()) :: boolean()
  def any_collision?(%__MODULE__{width: width, height: height} = board, piece) do
    Piece.cells_positions(piece)
    |> Enum.any?(fn {col, row, _color} ->
      col < 0 or col >= width or row >= height or
        (row >= 0 and get(board, col, row) != nil)
    end)
  end

  @spec find_matches(t()) :: t()
  def find_matches(%__MODULE__{width: width, height: height} = board) do
    board
    |> find_marked_positions(width, height)
    |> mark_positions(board)
  end

  defp find_marked_positions(board, width, height) do
    for col <- 0..(width - 2),
        row <- 0..(height - 2),
        match_at?(board, col, row),
        pos <- [{col, row}, {col + 1, row}, {col, row + 1}, {col + 1, row + 1}],
        into: MapSet.new() do
      pos
    end
  end

  defp mark_positions(positions, board) do
    Enum.reduce(positions, board, fn {col, row}, acc ->
      case get(acc, col, row) do
        {:marked, _} -> acc
        color when color in [:dark, :light] -> put(acc, col, row, {:marked, color})
        _ -> acc
      end
    end)
  end

  defp match_at?(board, col, row) do
    cells = [
      cell_color(get(board, col, row)),
      cell_color(get(board, col + 1, row)),
      cell_color(get(board, col, row + 1)),
      cell_color(get(board, col + 1, row + 1))
    ]

    case cells do
      [c, c, c, c] when not is_nil(c) -> true
      _ -> false
    end
  end

  defp cell_color(:dark), do: :dark
  defp cell_color(:light), do: :light
  defp cell_color({:marked, color}), do: color
  defp cell_color(_), do: nil

  @spec apply_gravity(t()) :: t()
  def apply_gravity(%__MODULE__{width: width} = board) do
    Enum.reduce(0..(width - 1), board, fn col, acc ->
      apply_column_gravity(acc, col)
    end)
  end

  defp apply_column_gravity(%__MODULE__{height: height} = board, col) do
    tiles = collect_column_tiles(board, col, height)
    empty_count = height - length(tiles)
    new_cells = rebuild_column(board.cells, col, height, empty_count, tiles)
    %{board | cells: new_cells}
  end

  defp collect_column_tiles(board, col, height) do
    for row <- 0..(height - 1),
        cell = get(board, col, row),
        not is_nil(cell) do
      cell
    end
  end

  defp rebuild_column(cells, col, height, empty_count, tiles) do
    Enum.reduce(0..(height - 1), cells, fn row, cells_acc ->
      value = if row < empty_count, do: nil, else: Enum.at(tiles, row - empty_count)

      case value do
        nil -> Map.delete(cells_acc, {col, row})
        v -> Map.put(cells_acc, {col, row}, v)
      end
    end)
  end

  @spec clear_marked_in_range(t(), non_neg_integer(), non_neg_integer()) ::
          {t(), non_neg_integer()}
  def clear_marked_in_range(%__MODULE__{height: height} = board, from_col, to_col) do
    from_col..to_col//1
    |> Enum.flat_map(fn col -> Enum.map(0..(height - 1), &{col, &1}) end)
    |> Enum.reduce({board, 0}, fn {col, row}, {b_acc, count} ->
      case get(b_acc, col, row) do
        {:marked, _} -> {put(b_acc, col, row, nil), count + 1}
        _ -> {b_acc, count}
      end
    end)
  end

  @spec topped_out?(t()) :: boolean()
  def topped_out?(%__MODULE__{width: width} = board) do
    Enum.any?(0..(width - 1), fn col ->
      get(board, col, 0) != nil
    end)
  end

  @spec has_marks?(t()) :: boolean()
  def has_marks?(%__MODULE__{cells: cells}) do
    Enum.any?(cells, fn
      {_pos, {:marked, _}} -> true
      _ -> false
    end)
  end

  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{cells: cells}) do
    map_size(cells) == 0
  end

  @spec single_color?(t()) :: boolean()
  def single_color?(%__MODULE__{cells: cells}) do
    colors =
      cells
      |> Map.values()
      |> Enum.map(&cell_color/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    match?([_], colors)
  end
end
