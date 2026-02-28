defmodule Illuminates.Eclipse.PieceTest do
  use ExUnit.Case, async: true

  alias Illuminates.Eclipse.Piece

  describe "random/0" do
    test "returns a piece with valid pattern" do
      piece = Piece.random()
      assert piece.cells in Piece.patterns()
      assert piece.col == 11
      assert piece.row == 0
    end
  end

  describe "rotate_cw/1" do
    test "rotates cells clockwise" do
      piece = %Piece{cells: {:dark, :light, :light, :dark}, col: 5, row: 3}
      rotated = Piece.rotate_cw(piece)
      assert rotated.cells == {:light, :dark, :dark, :light}
      assert rotated.col == 5
      assert rotated.row == 3
    end

    test "four clockwise rotations return to original" do
      piece = %Piece{cells: {:dark, :light, :light, :dark}, col: 0, row: 0}

      result =
        piece
        |> Piece.rotate_cw()
        |> Piece.rotate_cw()
        |> Piece.rotate_cw()
        |> Piece.rotate_cw()

      assert result.cells == piece.cells
    end
  end

  describe "rotate_ccw/1" do
    test "is inverse of rotate_cw" do
      piece = %Piece{cells: {:dark, :light, :light, :dark}, col: 0, row: 0}

      result =
        piece
        |> Piece.rotate_cw()
        |> Piece.rotate_ccw()

      assert result.cells == piece.cells
    end
  end

  describe "cells_positions/1" do
    test "returns four positions offset by piece location" do
      piece = %Piece{cells: {:dark, :light, :light, :dark}, col: 5, row: 3}
      positions = Piece.cells_positions(piece)

      assert positions == [
               {5, 3, :dark},
               {6, 3, :light},
               {5, 4, :light},
               {6, 4, :dark}
             ]
    end
  end

  describe "move/2" do
    test "moves left" do
      piece = %Piece{cells: {:dark, :dark, :dark, :dark}, col: 5, row: 3}
      assert Piece.move(piece, :left).col == 4
    end

    test "moves right" do
      piece = %Piece{cells: {:dark, :dark, :dark, :dark}, col: 5, row: 3}
      assert Piece.move(piece, :right).col == 6
    end

    test "moves down" do
      piece = %Piece{cells: {:dark, :dark, :dark, :dark}, col: 5, row: 3}
      assert Piece.move(piece, :down).row == 4
    end
  end
end
