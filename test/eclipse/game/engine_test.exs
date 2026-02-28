defmodule Eclipse.Game.EngineTest do
  use ExUnit.Case, async: true

  alias Eclipse.Game.Board
  alias Eclipse.Game.Engine
  alias Eclipse.Game.Piece

  describe "new_game/1" do
    test "initializes with active piece and queue" do
      state = Engine.new_game()
      assert state.active_piece != nil
      assert length(state.queue) == 3
      assert state.phase == :waiting
      assert state.board.width == 24
      assert state.board.height == 10
    end
  end

  describe "start/1" do
    test "transitions to playing" do
      state = Engine.new_game() |> Engine.start()
      assert state.phase == :playing
    end
  end

  describe "gravity_tick/1" do
    test "moves piece down one row" do
      state = Engine.new_game() |> Engine.start()
      original_row = state.active_piece.row
      ticked = Engine.gravity_tick(state)
      assert ticked.active_piece.row == original_row + 1
    end

    test "locks piece when it hits bottom" do
      state = Engine.new_game() |> Engine.start()
      piece = %Piece{cells: {:dark, :dark, :dark, :dark}, col: 5, row: 8}
      state = %{state | active_piece: piece}

      ticked = Engine.gravity_tick(state)

      assert ticked.active_piece != piece
      assert Board.get(ticked.board, 5, 8) != nil
    end

    test "detects game over when topped out" do
      state = Engine.new_game() |> Engine.start()

      # Fill entire board so gravity can't settle anything — board is full
      board =
        Enum.reduce(0..23, state.board, fn col, b ->
          Enum.reduce(0..9, b, fn row, b2 ->
            Board.put(b2, col, row, if(rem(col + row, 2) == 0, do: :dark, else: :light))
          end)
        end)

      piece = %Piece{cells: {:dark, :dark, :dark, :dark}, col: 5, row: -1}
      state = %{state | board: board, active_piece: piece}

      ticked = Engine.gravity_tick(state)
      assert ticked.phase == :game_over
    end
  end

  describe "move_left/1 and move_right/1" do
    test "moves piece left" do
      state = Engine.new_game() |> Engine.start()
      original_col = state.active_piece.col
      moved = Engine.move_left(state)
      assert moved.active_piece.col == original_col - 1
    end

    test "moves piece right" do
      state = Engine.new_game() |> Engine.start()
      original_col = state.active_piece.col
      moved = Engine.move_right(state)
      assert moved.active_piece.col == original_col + 1
    end

    test "does not move left past wall" do
      state = Engine.new_game() |> Engine.start()
      piece = %{state.active_piece | col: 0}
      state = %{state | active_piece: piece}
      moved = Engine.move_left(state)
      assert moved.active_piece.col == 0
    end

    test "does not move right past wall" do
      state = Engine.new_game() |> Engine.start()
      piece = %{state.active_piece | col: 22}
      state = %{state | active_piece: piece}
      moved = Engine.move_right(state)
      assert moved.active_piece.col == 22
    end
  end

  describe "rotate_cw/1" do
    test "rotates piece clockwise" do
      state = Engine.new_game() |> Engine.start()
      piece = %Piece{cells: {:dark, :light, :light, :dark}, col: 11, row: 0}
      state = %{state | active_piece: piece}
      rotated = Engine.rotate_cw(state)
      assert rotated.active_piece.cells == {:light, :dark, :dark, :light}
    end

    test "no-op when not playing" do
      state = Engine.new_game()
      assert state.phase == :waiting
      assert Engine.rotate_cw(state) == state
    end
  end

  describe "rotate_ccw/1" do
    test "rotates piece counter-clockwise" do
      state = Engine.new_game() |> Engine.start()
      piece = %Piece{cells: {:dark, :light, :light, :dark}, col: 11, row: 0}
      state = %{state | active_piece: piece}
      rotated = Engine.rotate_ccw(state)
      assert rotated.active_piece.cells == {:light, :dark, :dark, :light}
    end
  end

  describe "soft_drop/1" do
    test "moves piece down one row" do
      state = Engine.new_game() |> Engine.start()
      original_row = state.active_piece.row
      dropped = Engine.soft_drop(state)
      assert dropped.active_piece.row == original_row + 1
    end

    test "locks piece when at bottom" do
      state = Engine.new_game() |> Engine.start()
      piece = %Piece{cells: {:dark, :dark, :dark, :dark}, col: 5, row: 8}
      state = %{state | active_piece: piece}

      dropped = Engine.soft_drop(state)
      assert dropped.active_piece != piece
      assert Board.get(dropped.board, 5, 8) != nil
    end

    test "no-op when not playing" do
      state = Engine.new_game()
      assert Engine.soft_drop(state) == state
    end
  end

  describe "hard_drop/1" do
    test "places piece at bottom and locks" do
      state = Engine.new_game() |> Engine.start()
      piece = %Piece{cells: {:dark, :dark, :dark, :dark}, col: 5, row: 0}
      state = %{state | active_piece: piece}

      dropped = Engine.hard_drop(state)

      # All-dark 2x2 gets marked immediately after locking
      assert Board.get(dropped.board, 5, 8) == {:marked, :dark}
      assert Board.get(dropped.board, 6, 8) == {:marked, :dark}
      assert Board.get(dropped.board, 5, 9) == {:marked, :dark}
      assert Board.get(dropped.board, 6, 9) == {:marked, :dark}
      # New piece spawned from queue
      assert dropped.active_piece.row == 0
    end
  end

  describe "lock_piece applies gravity" do
    test "settling floating tiles immediately on lock" do
      # Build a board with a gap: tiles at rows 5-6, empty at rows 7-8, floor at row 9
      board =
        Board.new()
        |> Board.put(5, 5, :light)
        |> Board.put(5, 6, :dark)
        # rows 7,8 empty (gap from previous clear)
        |> Board.put(5, 9, :dark)

      state = Engine.new_game() |> Engine.start()
      # Place a piece that will lock on col 10 (away from our test column)
      # so lock_piece triggers gravity across the whole board
      piece = %Piece{cells: {:dark, :light, :light, :dark}, col: 10, row: 8}
      state = %{state | board: board, active_piece: piece}

      locked = Engine.gravity_tick(state)

      # The floating tiles at col 5 should have settled down
      # Original: row 5 = :light, row 6 = :dark, row 9 = :dark
      # After gravity: row 7 = :light, row 8 = :dark, row 9 = :dark
      assert Board.get(locked.board, 5, 7) == :light
      assert Board.get(locked.board, 5, 8) == :dark
      assert Board.get(locked.board, 5, 9) == :dark
      # Old positions should be empty
      assert Board.get(locked.board, 5, 5) == nil
      assert Board.get(locked.board, 5, 6) == nil
    end

    test "hard drop settles floating tiles from previous clears" do
      # Simulate a board where previous scanner clears left gaps
      board =
        Board.new()
        |> Board.put(3, 2, :light)
        |> Board.put(3, 3, :light)
        # rows 4-8 empty (cleared by scanner)
        |> Board.put(3, 9, :dark)

      state = Engine.new_game() |> Engine.start()
      piece = %Piece{cells: {:dark, :light, :light, :dark}, col: 12, row: 0}
      state = %{state | board: board, active_piece: piece}

      dropped = Engine.hard_drop(state)

      # Floating tiles at col 3 should have settled
      # Original: row 2 = :light, row 3 = :light, row 9 = :dark
      # After gravity: row 7 = :light, row 8 = :light, row 9 = :dark
      assert Board.get(dropped.board, 3, 7) == :light
      assert Board.get(dropped.board, 3, 8) == :light
      assert Board.get(dropped.board, 3, 9) == :dark
      assert Board.get(dropped.board, 3, 2) == nil
      assert Board.get(dropped.board, 3, 3) == nil
    end
  end

  describe "scanner_tick/1" do
    test "advances scanner position" do
      state = Engine.new_game() |> Engine.start()
      original_pos = state.scanner.position
      ticked = Engine.scanner_tick(state)
      assert ticked.scanner.position > original_pos
    end

    test "clears marked tiles when scanner passes" do
      state = Engine.new_game() |> Engine.start()

      board =
        state.board
        |> Board.put(0, 8, {:marked, :dark})
        |> Board.put(1, 8, {:marked, :dark})
        |> Board.put(0, 9, {:marked, :dark})
        |> Board.put(1, 9, {:marked, :dark})

      scanner = %{state.scanner | position: 0.0, speed: 2.0}
      state = %{state | board: board, scanner: scanner}

      ticked = Engine.scanner_tick(state)

      assert Board.get(ticked.board, 0, 8) == nil
      assert Board.get(ticked.board, 1, 8) == nil
      assert ticked.score > 0
    end

    test "no-op when not playing" do
      state = Engine.new_game()
      assert Engine.scanner_tick(state) == state
    end
  end

  describe "level up" do
    test "levels up when lines_cleared crosses threshold" do
      state = Engine.new_game() |> Engine.start()

      # Set up state just below level-up threshold (50 lines per level)
      board =
        state.board
        |> Board.put(0, 8, {:marked, :dark})
        |> Board.put(1, 8, {:marked, :dark})
        |> Board.put(0, 9, {:marked, :dark})
        |> Board.put(1, 9, {:marked, :dark})

      scanner = %{state.scanner | position: 0.0, speed: 2.0}
      state = %{state | board: board, scanner: scanner, lines_cleared: 48, level: 1}

      ticked = Engine.scanner_tick(state)

      assert ticked.lines_cleared >= 50
      assert ticked.level == 2
      assert ticked.gravity_interval < 1000
    end

    test "does not level up below threshold" do
      state = Engine.new_game() |> Engine.start()

      board =
        state.board
        |> Board.put(0, 8, {:marked, :dark})
        |> Board.put(1, 8, {:marked, :dark})
        |> Board.put(0, 9, {:marked, :dark})
        |> Board.put(1, 9, {:marked, :dark})

      scanner = %{state.scanner | position: 0.0, speed: 2.0}
      state = %{state | board: board, scanner: scanner, lines_cleared: 0, level: 1}

      ticked = Engine.scanner_tick(state)

      assert ticked.level == 1
      assert ticked.gravity_interval == 1000
    end
  end

  describe "no-op guards" do
    test "move_left no-op when not playing" do
      state = Engine.new_game()
      assert Engine.move_left(state) == state
    end

    test "move_right no-op when not playing" do
      state = Engine.new_game()
      assert Engine.move_right(state) == state
    end

    test "hard_drop no-op when not playing" do
      state = Engine.new_game()
      assert Engine.hard_drop(state) == state
    end

    test "gravity_tick no-op when not playing" do
      state = Engine.new_game()
      assert Engine.gravity_tick(state) == state
    end
  end
end
