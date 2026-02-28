defmodule Illuminates.Eclipse.GameTest do
  use ExUnit.Case, async: true

  alias Illuminates.Eclipse.Board
  alias Illuminates.Eclipse.Game
  alias Illuminates.Eclipse.Piece

  describe "new_game/1" do
    test "initializes with active piece and queue" do
      state = Game.new_game()
      assert state.active_piece != nil
      assert length(state.queue) == 3
      assert state.phase == :waiting
      assert state.board.width == 24
      assert state.board.height == 10
    end
  end

  describe "start/1" do
    test "transitions to playing" do
      state = Game.new_game() |> Game.start()
      assert state.phase == :playing
    end
  end

  describe "gravity_tick/1" do
    test "moves piece down one row" do
      state = Game.new_game() |> Game.start()
      original_row = state.active_piece.row
      ticked = Game.gravity_tick(state)
      assert ticked.active_piece.row == original_row + 1
    end

    test "locks piece when it hits bottom" do
      state = Game.new_game() |> Game.start()
      piece = %Piece{cells: {:dark, :dark, :dark, :dark}, col: 5, row: 8}
      state = %{state | active_piece: piece}

      ticked = Game.gravity_tick(state)

      assert ticked.active_piece != piece
      assert Board.get(ticked.board, 5, 8) != nil
    end

    test "detects game over when topped out" do
      state = Game.new_game() |> Game.start()

      board =
        Enum.reduce(0..23, state.board, fn col, b ->
          Board.put(b, col, 0, :dark)
        end)

      piece = %Piece{cells: {:dark, :dark, :dark, :dark}, col: 5, row: -1}
      state = %{state | board: board, active_piece: piece}

      ticked = Game.gravity_tick(state)
      assert ticked.phase == :game_over
    end
  end

  describe "move_left/1 and move_right/1" do
    test "moves piece left" do
      state = Game.new_game() |> Game.start()
      original_col = state.active_piece.col
      moved = Game.move_left(state)
      assert moved.active_piece.col == original_col - 1
    end

    test "moves piece right" do
      state = Game.new_game() |> Game.start()
      original_col = state.active_piece.col
      moved = Game.move_right(state)
      assert moved.active_piece.col == original_col + 1
    end

    test "does not move left past wall" do
      state = Game.new_game() |> Game.start()
      piece = %{state.active_piece | col: 0}
      state = %{state | active_piece: piece}
      moved = Game.move_left(state)
      assert moved.active_piece.col == 0
    end

    test "does not move right past wall" do
      state = Game.new_game() |> Game.start()
      piece = %{state.active_piece | col: 22}
      state = %{state | active_piece: piece}
      moved = Game.move_right(state)
      assert moved.active_piece.col == 22
    end
  end

  describe "rotate_cw/1" do
    test "rotates piece clockwise" do
      state = Game.new_game() |> Game.start()
      piece = %Piece{cells: {:dark, :light, :light, :dark}, col: 11, row: 0}
      state = %{state | active_piece: piece}
      rotated = Game.rotate_cw(state)
      assert rotated.active_piece.cells == {:light, :dark, :dark, :light}
    end
  end

  describe "hard_drop/1" do
    test "places piece at bottom and locks" do
      state = Game.new_game() |> Game.start()
      piece = %Piece{cells: {:dark, :dark, :dark, :dark}, col: 5, row: 0}
      state = %{state | active_piece: piece}

      dropped = Game.hard_drop(state)

      # All-dark 2x2 gets marked immediately after locking
      assert Board.get(dropped.board, 5, 8) == {:marked, :dark}
      assert Board.get(dropped.board, 6, 8) == {:marked, :dark}
      assert Board.get(dropped.board, 5, 9) == {:marked, :dark}
      assert Board.get(dropped.board, 6, 9) == {:marked, :dark}
      # New piece spawned from queue
      assert dropped.active_piece.row == 0
    end
  end

  describe "scanner_tick/1" do
    test "advances scanner position" do
      state = Game.new_game() |> Game.start()
      original_pos = state.scanner.position
      ticked = Game.scanner_tick(state)
      assert ticked.scanner.position > original_pos
    end

    test "clears marked tiles when scanner passes" do
      state = Game.new_game() |> Game.start()

      board =
        state.board
        |> Board.put(0, 8, {:marked, :dark})
        |> Board.put(1, 8, {:marked, :dark})
        |> Board.put(0, 9, {:marked, :dark})
        |> Board.put(1, 9, {:marked, :dark})

      scanner = %{state.scanner | position: 0.0, speed: 2.0}
      state = %{state | board: board, scanner: scanner}

      ticked = Game.scanner_tick(state)

      assert Board.get(ticked.board, 0, 8) == nil
      assert Board.get(ticked.board, 1, 8) == nil
      assert ticked.score > 0
    end
  end
end
