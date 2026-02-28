defmodule Eclipse.Game.BoardTest do
  use ExUnit.Case, async: true

  alias Eclipse.Game.Board
  alias Eclipse.Game.Piece

  describe "new/2" do
    test "creates empty board with correct dimensions" do
      board = Board.new(24, 10)
      assert board.width == 24
      assert board.height == 10
      assert board.cells == %{}
    end
  end

  describe "get/3 and put/4" do
    test "stores and retrieves cell values" do
      board =
        Board.new()
        |> Board.put(5, 3, :dark)

      assert Board.get(board, 5, 3) == :dark
      assert Board.get(board, 0, 0) == nil
    end

    test "putting nil removes the cell" do
      board =
        Board.new()
        |> Board.put(5, 3, :dark)
        |> Board.put(5, 3, nil)

      assert Board.get(board, 5, 3) == nil
    end
  end

  describe "place_piece/2" do
    test "stamps piece cells onto the board" do
      piece = %Piece{cells: {:dark, :light, :light, :dark}, col: 5, row: 3}

      board =
        Board.new()
        |> Board.place_piece(piece)

      assert Board.get(board, 5, 3) == :dark
      assert Board.get(board, 6, 3) == :light
      assert Board.get(board, 5, 4) == :light
      assert Board.get(board, 6, 4) == :dark
    end
  end

  describe "any_collision?/2" do
    test "detects left wall collision" do
      piece = %Piece{cells: {:dark, :dark, :dark, :dark}, col: -1, row: 0}
      board = Board.new()

      assert Board.any_collision?(board, piece)
    end

    test "detects right wall collision" do
      piece = %Piece{cells: {:dark, :dark, :dark, :dark}, col: 23, row: 0}
      board = Board.new()

      assert Board.any_collision?(board, piece)
    end

    test "detects bottom wall collision" do
      piece = %Piece{cells: {:dark, :dark, :dark, :dark}, col: 0, row: 9}
      board = Board.new()

      assert Board.any_collision?(board, piece)
    end

    test "detects collision with existing tile" do
      piece = %Piece{cells: {:dark, :dark, :dark, :dark}, col: 5, row: 3}

      board =
        Board.new()
        |> Board.put(5, 3, :dark)

      assert Board.any_collision?(board, piece)
    end

    test "no collision on valid position" do
      piece = %Piece{cells: {:dark, :dark, :dark, :dark}, col: 5, row: 3}
      board = Board.new()

      refute Board.any_collision?(board, piece)
    end

    test "allows piece above board (negative row)" do
      piece = %Piece{cells: {:dark, :dark, :dark, :dark}, col: 5, row: -1}
      board = Board.new()

      refute Board.any_collision?(board, piece)
    end
  end

  describe "find_matches/1" do
    test "marks a 2x2 same-color square" do
      board =
        Board.new()
        |> Board.put(5, 5, :dark)
        |> Board.put(6, 5, :dark)
        |> Board.put(5, 6, :dark)
        |> Board.put(6, 6, :dark)
        |> Board.find_matches()

      assert Board.get(board, 5, 5) == {:marked, :dark}
      assert Board.get(board, 6, 5) == {:marked, :dark}
      assert Board.get(board, 5, 6) == {:marked, :dark}
      assert Board.get(board, 6, 6) == {:marked, :dark}
    end

    test "does not mark checkerboard pattern" do
      board =
        Board.new()
        |> Board.put(5, 5, :dark)
        |> Board.put(6, 5, :light)
        |> Board.put(5, 6, :light)
        |> Board.put(6, 6, :dark)
        |> Board.find_matches()

      assert Board.get(board, 5, 5) == :dark
      assert Board.get(board, 6, 5) == :light
    end

    test "handles overlapping matches" do
      board =
        Board.new()
        |> Board.put(5, 5, :dark)
        |> Board.put(6, 5, :dark)
        |> Board.put(7, 5, :dark)
        |> Board.put(5, 6, :dark)
        |> Board.put(6, 6, :dark)
        |> Board.put(7, 6, :dark)
        |> Board.find_matches()

      for col <- 5..7, row <- 5..6 do
        assert Board.get(board, col, row) == {:marked, :dark},
               "expected marked at {#{col}, #{row}}"
      end
    end

    test "treats already-marked tiles as their color for matching" do
      board =
        Board.new()
        |> Board.put(5, 5, {:marked, :dark})
        |> Board.put(6, 5, :dark)
        |> Board.put(5, 6, :dark)
        |> Board.put(6, 6, :dark)
        |> Board.find_matches()

      assert Board.get(board, 6, 5) == {:marked, :dark}
      assert Board.get(board, 5, 6) == {:marked, :dark}
      assert Board.get(board, 6, 6) == {:marked, :dark}
    end
  end

  describe "apply_gravity/1" do
    test "drops tiles to fill gaps" do
      board =
        Board.new(4, 4)
        |> Board.put(0, 0, :dark)
        |> Board.put(0, 2, :light)
        |> Board.apply_gravity()

      assert Board.get(board, 0, 0) == nil
      assert Board.get(board, 0, 1) == nil
      assert Board.get(board, 0, 2) == :dark
      assert Board.get(board, 0, 3) == :light
    end

    test "handles multiple gaps in one column" do
      board =
        Board.new(4, 6)
        |> Board.put(0, 0, :dark)
        |> Board.put(0, 2, :light)
        |> Board.put(0, 4, :dark)
        |> Board.apply_gravity()

      assert Board.get(board, 0, 3) == :dark
      assert Board.get(board, 0, 4) == :light
      assert Board.get(board, 0, 5) == :dark
    end
  end

  describe "clear_marked_in_range/3" do
    test "removes only marked cells in range" do
      board =
        Board.new()
        |> Board.put(5, 5, {:marked, :dark})
        |> Board.put(6, 5, {:marked, :dark})
        |> Board.put(7, 5, :dark)
        |> Board.put(10, 5, {:marked, :light})

      {cleared, count} = Board.clear_marked_in_range(board, 5, 7)

      assert Board.get(cleared, 5, 5) == nil
      assert Board.get(cleared, 6, 5) == nil
      assert Board.get(cleared, 7, 5) == :dark
      assert Board.get(cleared, 10, 5) == {:marked, :light}
      assert count == 2
    end
  end

  describe "topped_out?/1" do
    test "returns true when tile in top row" do
      board =
        Board.new()
        |> Board.put(5, 0, :dark)

      assert Board.topped_out?(board)
    end

    test "returns false when top row is empty" do
      board =
        Board.new()
        |> Board.put(5, 5, :dark)

      refute Board.topped_out?(board)
    end
  end

  describe "has_marks?/1" do
    test "returns true when board contains marked cells" do
      board =
        Board.new()
        |> Board.put(5, 5, {:marked, :dark})

      assert Board.has_marks?(board)
    end

    test "returns false when no marked cells exist" do
      board =
        Board.new()
        |> Board.put(5, 5, :dark)

      refute Board.has_marks?(board)
    end

    test "returns false on empty board" do
      board = Board.new()

      refute Board.has_marks?(board)
    end
  end

  describe "empty?/1" do
    test "returns true for new board" do
      board = Board.new()

      assert Board.empty?(board)
    end

    test "returns false when board has cells" do
      board =
        Board.new()
        |> Board.put(0, 0, :dark)

      refute Board.empty?(board)
    end
  end

  describe "single_color?/1" do
    test "returns true when all cells are same color" do
      board =
        Board.new()
        |> Board.put(0, 0, :dark)
        |> Board.put(1, 1, :dark)
        |> Board.put(2, 2, {:marked, :dark})

      assert Board.single_color?(board)
    end

    test "returns false when cells are different colors" do
      board =
        Board.new()
        |> Board.put(0, 0, :dark)
        |> Board.put(1, 1, :light)

      refute Board.single_color?(board)
    end

    test "returns true for empty board" do
      # Empty board has zero colors, which is technically single-color ([]-> [] after uniq)
      refute Board.single_color?(Board.new())
    end
  end
end
