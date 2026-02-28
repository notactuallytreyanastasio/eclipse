defmodule EclipseWeb.GameLiveIntegrationTest do
  @moduledoc """
  Integration tests that exercise the real LiveView process with actual game
  mechanics — gravity ticks, scanner sweeps, piece locking, chain reactions,
  game over, restart, and level-up. These send real messages to the LiveView
  pid and assert on resulting game state, not just HTML structure.
  """

  use EclipseWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Eclipse.Game.Board
  alias Eclipse.Game.GameState
  alias Eclipse.Game.Piece
  alias Eclipse.Game.Scanner

  # ── Helpers ──────────────────────────────────────────────────────────

  defp start_game(conn) do
    {:ok, view, _html} = live(conn, ~p"/play")
    view |> element("#start-btn") |> render_click()
    view
  end

  defp game_state(view) do
    :sys.get_state(view.pid)
    |> get_in([Access.key(:socket), Access.key(:assigns), Access.key(:game)])
  end

  defp inject_game_state(view, %GameState{} = game) do
    :sys.replace_state(view.pid, fn state ->
      # Cancel any pending timers to prevent races
      assigns = get_in(state, [Access.key(:socket), Access.key(:assigns)])

      if assigns[:gravity_ref], do: Process.cancel_timer(assigns.gravity_ref)
      if assigns[:scanner_ref], do: Process.cancel_timer(assigns.scanner_ref)

      state
      |> put_in([Access.key(:socket), Access.key(:assigns), :game], game)
      |> put_in([Access.key(:socket), Access.key(:assigns), :gravity_ref], nil)
      |> put_in([Access.key(:socket), Access.key(:assigns), :scanner_ref], nil)
    end)

    # Flush any timer messages that were already in the mailbox
    flush_timer_messages(view.pid)

    # Synchronize — ensure LiveView re-renders with new state
    _ = render(view)
  end

  defp flush_timer_messages(pid) do
    # Drain any :gravity_tick or :scanner_tick messages from the process mailbox
    # by sending a sync message and waiting for it
    _ = :sys.get_state(pid)
  end

  # Build a playing game state with a controlled board and piece.
  # Bypasses random queue by constructing everything explicitly.
  defp build_playing_state(opts) do
    board = Keyword.get(opts, :board, Board.new())
    piece = Keyword.get(opts, :piece, %Piece{cells: {:dark, :dark, :dark, :dark}, col: 5, row: 0})
    scanner = Keyword.get(opts, :scanner, %Scanner{position: 0.0, speed: 0.0625})
    score = Keyword.get(opts, :score, 0)
    level = Keyword.get(opts, :level, 1)
    lines_cleared = Keyword.get(opts, :lines_cleared, 0)
    gravity_interval = Keyword.get(opts, :gravity_interval, 1000)
    scanner_interval = Keyword.get(opts, :scanner_interval, 50)

    queue =
      Keyword.get(opts, :queue, [
        %Piece{cells: {:dark, :dark, :dark, :dark}, col: 11, row: 0},
        %Piece{cells: {:light, :light, :light, :light}, col: 11, row: 0},
        %Piece{cells: {:dark, :light, :light, :dark}, col: 11, row: 0}
      ])

    %GameState{
      board: board,
      active_piece: piece,
      queue: queue,
      scanner: scanner,
      score: score,
      level: level,
      lines_cleared: lines_cleared,
      phase: :playing,
      gravity_interval: gravity_interval,
      scanner_interval: scanner_interval
    }
  end

  # ── Gravity / Falling ───────────────────────────────────────────────

  describe "gravity tick via LiveView messaging" do
    test "piece falls one row per gravity tick", %{conn: conn} do
      view = start_game(conn)
      game_before = game_state(view)
      initial_row = game_before.active_piece.row

      send(view.pid, :gravity_tick)
      _ = render(view)

      game_after = game_state(view)
      assert game_after.active_piece.row == initial_row + 1
    end

    test "multiple gravity ticks move piece progressively down", %{conn: conn} do
      view = start_game(conn)
      game_before = game_state(view)
      initial_row = game_before.active_piece.row

      for _ <- 1..5 do
        send(view.pid, :gravity_tick)
      end

      _ = render(view)

      game_after = game_state(view)
      assert game_after.active_piece.row == initial_row + 5
    end

    test "piece locks when it hits the bottom and new piece spawns", %{conn: conn} do
      view = start_game(conn)

      # Place piece near bottom: board is 10 rows, piece is 2 tall,
      # so row 8 means bottom cells at row 9. One more tick = collision.
      state =
        build_playing_state(piece: %Piece{cells: {:dark, :dark, :dark, :dark}, col: 5, row: 8})

      inject_game_state(view, state)

      # This tick tries to move to row 9 — bottom cells would be at row 10 (out of bounds)
      send(view.pid, :gravity_tick)
      _ = render(view)

      game = game_state(view)

      # Piece locked: board should have tiles at the old position
      assert Board.get(game.board, 5, 8) != nil
      assert Board.get(game.board, 6, 8) != nil
      assert Board.get(game.board, 5, 9) != nil
      assert Board.get(game.board, 6, 9) != nil

      # New piece spawned from queue
      assert game.active_piece != nil
      assert game.active_piece.row == 0
    end

    test "piece locks when it lands on existing tiles", %{conn: conn} do
      view = start_game(conn)

      # Put some tiles on the board at row 6, piece at row 4
      board =
        Board.new()
        |> Board.put(5, 6, :light)
        |> Board.put(6, 6, :light)

      state =
        build_playing_state(
          board: board,
          piece: %Piece{cells: {:dark, :dark, :dark, :dark}, col: 5, row: 4}
        )

      inject_game_state(view, state)

      # Tick: piece moves to row 5 (bottom cells at row 6 collide with existing tiles)
      send(view.pid, :gravity_tick)
      _ = render(view)

      game = game_state(view)

      # Piece locked at row 4, then gravity settles tiles to bottom:
      # col 5/6 had 3 tiles each (rows 4,5,6) → gravity packs to rows 7,8,9
      # All-dark 2x2 at rows 7-8 forms a match, so those are marked
      assert Board.get(game.board, 5, 7) == {:marked, :dark}
      assert Board.get(game.board, 6, 7) == {:marked, :dark}
      assert Board.get(game.board, 5, 8) == {:marked, :dark}
      assert Board.get(game.board, 6, 8) == {:marked, :dark}

      # Original light tiles settled to row 9
      assert Board.get(game.board, 5, 9) == :light
      assert Board.get(game.board, 6, 9) == :light
    end
  end

  # ── Hard Drop ───────────────────────────────────────────────────────

  describe "hard drop via LiveView" do
    test "piece drops instantly to bottom", %{conn: conn} do
      view = start_game(conn)

      # Use checkerboard pattern so it won't form a 2x2 match on lock
      state =
        build_playing_state(piece: %Piece{cells: {:dark, :light, :light, :dark}, col: 5, row: 0})

      inject_game_state(view, state)

      render_keydown(view, "keydown", %{"key" => " "})

      game = game_state(view)

      # Piece should have locked at the bottom (rows 8-9 on a 10-row board)
      # Checkerboard won't match, so plain colors
      assert Board.get(game.board, 5, 8) == :dark
      assert Board.get(game.board, 6, 8) == :light
      assert Board.get(game.board, 5, 9) == :light
      assert Board.get(game.board, 6, 9) == :dark

      # New piece spawned
      assert game.active_piece != nil
      assert game.active_piece.row == 0
    end

    test "hard drop onto existing tiles stops at correct row", %{conn: conn} do
      view = start_game(conn)

      # Use checkerboard existing tiles (no match possible)
      board =
        Board.new()
        |> Board.put(5, 8, :light)
        |> Board.put(6, 8, :dark)
        |> Board.put(5, 9, :dark)
        |> Board.put(6, 9, :light)

      # Use checkerboard piece too — no 2x2 match
      state =
        build_playing_state(
          board: board,
          piece: %Piece{cells: {:dark, :light, :light, :dark}, col: 5, row: 0}
        )

      inject_game_state(view, state)

      render_keydown(view, "keydown", %{"key" => " "})

      game = game_state(view)

      # Dropped piece should land at rows 6-7 (just above existing tiles at 8-9)
      assert Board.get(game.board, 5, 6) == :dark
      assert Board.get(game.board, 6, 6) == :light
      assert Board.get(game.board, 5, 7) == :light
      assert Board.get(game.board, 6, 7) == :dark

      # Original tiles unchanged
      assert Board.get(game.board, 5, 8) == :light
      assert Board.get(game.board, 6, 8) == :dark
    end
  end

  # ── Match Detection on Lock ─────────────────────────────────────────

  describe "2x2 match detection when piece locks" do
    test "all-dark 2x2 piece landing creates marked tiles", %{conn: conn} do
      view = start_game(conn)

      state =
        build_playing_state(piece: %Piece{cells: {:dark, :dark, :dark, :dark}, col: 5, row: 0})

      inject_game_state(view, state)

      # Hard drop to bottom
      render_keydown(view, "keydown", %{"key" => " "})

      game = game_state(view)

      # All-dark 2x2 block at bottom should be marked
      assert Board.get(game.board, 5, 8) == {:marked, :dark}
      assert Board.get(game.board, 6, 8) == {:marked, :dark}
      assert Board.get(game.board, 5, 9) == {:marked, :dark}
      assert Board.get(game.board, 6, 9) == {:marked, :dark}
    end

    test "mixed-color piece does not create marks", %{conn: conn} do
      view = start_game(conn)

      # Checkerboard pattern — no 2x2 same-color match possible
      state =
        build_playing_state(piece: %Piece{cells: {:dark, :light, :light, :dark}, col: 5, row: 0})

      inject_game_state(view, state)

      render_keydown(view, "keydown", %{"key" => " "})

      game = game_state(view)

      # No marks — cells should be plain colors
      assert Board.get(game.board, 5, 8) == :dark
      assert Board.get(game.board, 6, 8) == :light
      assert Board.get(game.board, 5, 9) == :light
      assert Board.get(game.board, 6, 9) == :dark
    end

    test "piece landing next to same-color tiles creates larger match", %{conn: conn} do
      view = start_game(conn)

      # Pre-place dark tiles at cols 7-8, rows 8-9 (a 2x2 block at bottom right)
      board =
        Board.new()
        |> Board.put(7, 8, :dark)
        |> Board.put(8, 8, :dark)
        |> Board.put(7, 9, :dark)
        |> Board.put(8, 9, :dark)

      # All-dark piece at col 7, hard drops → lands on top at rows 6-7.
      # Piece at cols 7-8 rows 6-7 + existing at cols 7-8 rows 8-9.
      # Piece itself is a 2x2 dark block = marked. Existing is also 2x2 dark = marked.
      # Also cols 7-8 rows 7-8 forms another 2x2 across piece bottom and existing top.
      state =
        build_playing_state(
          board: board,
          piece: %Piece{cells: {:dark, :dark, :dark, :dark}, col: 7, row: 0}
        )

      inject_game_state(view, state)

      render_keydown(view, "keydown", %{"key" => " "})

      game = game_state(view)

      # All 8 cells should be marked: 3 overlapping 2x2 dark matches
      assert Board.get(game.board, 7, 6) == {:marked, :dark}
      assert Board.get(game.board, 8, 6) == {:marked, :dark}
      assert Board.get(game.board, 7, 7) == {:marked, :dark}
      assert Board.get(game.board, 8, 7) == {:marked, :dark}
      assert Board.get(game.board, 7, 8) == {:marked, :dark}
      assert Board.get(game.board, 8, 8) == {:marked, :dark}
      assert Board.get(game.board, 7, 9) == {:marked, :dark}
      assert Board.get(game.board, 8, 9) == {:marked, :dark}
    end
  end

  # ── Scanner Clearing ────────────────────────────────────────────────

  describe "scanner clearing via LiveView messaging" do
    test "scanner clears marked tiles as it sweeps past them", %{conn: conn} do
      view = start_game(conn)

      # Place marked tiles at column 0
      board =
        Board.new()
        |> Board.put(0, 8, {:marked, :dark})
        |> Board.put(0, 9, {:marked, :dark})
        |> Board.put(1, 8, {:marked, :dark})
        |> Board.put(1, 9, {:marked, :dark})

      # Scanner at position 0.0, speed high enough to cross column 0 in one tick
      state =
        build_playing_state(
          board: board,
          scanner: %Scanner{position: 0.0, speed: 1.0},
          piece: %Piece{cells: {:light, :light, :light, :light}, col: 11, row: 0}
        )

      inject_game_state(view, state)

      # Scanner tick should advance past column 0 and clear the marks
      send(view.pid, :scanner_tick)
      _ = render(view)

      game = game_state(view)

      # Column 0 marked tiles should be cleared (nil after gravity)
      assert Board.get(game.board, 0, 8) == nil
      assert Board.get(game.board, 0, 9) == nil
    end

    test "scanner awards score when clearing marked tiles", %{conn: conn} do
      view = start_game(conn)

      board =
        Board.new()
        |> Board.put(0, 8, {:marked, :dark})
        |> Board.put(0, 9, {:marked, :dark})
        |> Board.put(1, 8, {:marked, :dark})
        |> Board.put(1, 9, {:marked, :dark})

      state =
        build_playing_state(
          board: board,
          scanner: %Scanner{position: 0.0, speed: 2.0},
          score: 0,
          level: 1,
          piece: %Piece{cells: {:light, :dark, :dark, :light}, col: 11, row: 0}
        )

      inject_game_state(view, state)

      send(view.pid, :scanner_tick)
      _ = render(view)

      game = game_state(view)

      # 4 marked tiles cleared * 10 * level 1 = 40 points
      assert game.score == 40
    end

    test "scanner does not clear unmarked tiles", %{conn: conn} do
      view = start_game(conn)

      # Use checkerboard pattern — no 2x2 match, so find_matches won't mark them
      board =
        Board.new()
        |> Board.put(0, 8, :dark)
        |> Board.put(0, 9, :light)
        |> Board.put(1, 8, :light)
        |> Board.put(1, 9, :dark)

      state =
        build_playing_state(
          board: board,
          scanner: %Scanner{position: 0.0, speed: 2.0},
          piece: %Piece{cells: {:light, :dark, :dark, :light}, col: 11, row: 0}
        )

      inject_game_state(view, state)

      send(view.pid, :scanner_tick)
      _ = render(view)

      game = game_state(view)

      # Unmarked tiles should remain (checkerboard prevents marking)
      assert Board.get(game.board, 0, 8) == :dark
      assert Board.get(game.board, 0, 9) == :light
      assert Board.get(game.board, 1, 8) == :light
      assert Board.get(game.board, 1, 9) == :dark
    end

    test "scanner tick with no column crossing changes only position", %{conn: conn} do
      view = start_game(conn)

      state =
        build_playing_state(
          scanner: %Scanner{position: 5.0, speed: 0.1},
          piece: %Piece{cells: {:dark, :dark, :dark, :dark}, col: 11, row: 0}
        )

      inject_game_state(view, state)

      score_before = state.score
      send(view.pid, :scanner_tick)
      _ = render(view)

      game = game_state(view)

      # Scanner moved but no column crossed — score unchanged
      assert game.score == score_before
      assert game.scanner.position > 5.0
      assert trunc(game.scanner.position) == 5
    end
  end

  # ── Gravity After Clear (Falling) ──────────────────────────────────

  describe "gravity after scanner clears tiles" do
    test "tiles above cleared cells fall down", %{conn: conn} do
      view = start_game(conn)

      # Checkerboard tiles above marked tiles — won't form a match after falling
      board =
        Board.new()
        |> Board.put(0, 6, :dark)
        |> Board.put(1, 6, :light)
        |> Board.put(0, 7, :light)
        |> Board.put(1, 7, :dark)
        |> Board.put(0, 8, {:marked, :dark})
        |> Board.put(1, 8, {:marked, :dark})
        |> Board.put(0, 9, {:marked, :dark})
        |> Board.put(1, 9, {:marked, :dark})

      state =
        build_playing_state(
          board: board,
          scanner: %Scanner{position: 0.0, speed: 2.0},
          piece: %Piece{cells: {:dark, :light, :light, :dark}, col: 11, row: 0}
        )

      inject_game_state(view, state)

      # Scanner sweeps cols 0-1, clearing marked tiles, then gravity runs
      send(view.pid, :scanner_tick)
      _ = render(view)

      game = game_state(view)

      # Tiles should have fallen from rows 6-7 to rows 8-9 (checkerboard preserved)
      assert Board.get(game.board, 0, 8) == :dark
      assert Board.get(game.board, 1, 8) == :light
      assert Board.get(game.board, 0, 9) == :light
      assert Board.get(game.board, 1, 9) == :dark

      # Old positions should be empty
      assert Board.get(game.board, 0, 6) == nil
      assert Board.get(game.board, 1, 6) == nil
    end

    test "gravity after clear triggers new match detection", %{conn: conn} do
      view = start_game(conn)

      # Setup: light tiles at rows 6-7 in cols 0-1, marked dark below at rows 8-9.
      # After clearing dark marks at 8-9 and gravity, light tiles fall from 6-7 to 8-9.
      # That forms a 2x2 light block at rows 8-9 — newly marked.
      board =
        Board.new()
        |> Board.put(0, 6, :light)
        |> Board.put(1, 6, :light)
        |> Board.put(0, 7, :light)
        |> Board.put(1, 7, :light)
        |> Board.put(0, 8, {:marked, :dark})
        |> Board.put(1, 8, {:marked, :dark})
        |> Board.put(0, 9, {:marked, :dark})
        |> Board.put(1, 9, {:marked, :dark})

      state =
        build_playing_state(
          board: board,
          scanner: %Scanner{position: 0.0, speed: 2.0},
          piece: %Piece{cells: {:dark, :light, :light, :dark}, col: 11, row: 0}
        )

      inject_game_state(view, state)

      send(view.pid, :scanner_tick)
      _ = render(view)

      game = game_state(view)

      # After clearing rows 8-9, light tiles fall from rows 6-7 to 8-9.
      # That's a 2x2 light block — should be newly marked.
      assert Board.get(game.board, 0, 8) == {:marked, :light}
      assert Board.get(game.board, 1, 8) == {:marked, :light}
      assert Board.get(game.board, 0, 9) == {:marked, :light}
      assert Board.get(game.board, 1, 9) == {:marked, :light}

      # Old positions should be empty
      assert Board.get(game.board, 0, 6) == nil
      assert Board.get(game.board, 1, 6) == nil
    end
  end

  # ── Chain Reactions ─────────────────────────────────────────────────

  describe "chain reactions across multiple scanner sweeps" do
    test "first sweep clears marks, gravity creates new marks, second sweep clears those", %{
      conn: conn
    } do
      view = start_game(conn)

      # Setup chain: marked dark at rows 8-9, light tiles at rows 6-7.
      # Sweep 1: clear dark marks at 8-9, gravity drops light from 6-7 to 8-9.
      # Now 2x2 light block at rows 8-9 = newly marked.
      # Sweep 2: clear those new light marks.
      board =
        Board.new()
        |> Board.put(0, 6, :light)
        |> Board.put(1, 6, :light)
        |> Board.put(0, 7, :light)
        |> Board.put(1, 7, :light)
        |> Board.put(0, 8, {:marked, :dark})
        |> Board.put(1, 8, {:marked, :dark})
        |> Board.put(0, 9, {:marked, :dark})
        |> Board.put(1, 9, {:marked, :dark})

      state =
        build_playing_state(
          board: board,
          scanner: %Scanner{position: 0.0, speed: 2.0},
          piece: %Piece{cells: {:dark, :light, :light, :dark}, col: 11, row: 0}
        )

      inject_game_state(view, state)

      # First sweep: clears dark marks, gravity drops light tiles, forms new 2x2 marks
      send(view.pid, :scanner_tick)
      _ = render(view)

      game_after_first = game_state(view)
      assert game_after_first.score > 0

      # Light tiles should now be marked at rows 8-9 (chain reaction)
      assert Board.get(game_after_first.board, 0, 8) == {:marked, :light}
      assert Board.get(game_after_first.board, 1, 8) == {:marked, :light}
      assert Board.get(game_after_first.board, 0, 9) == {:marked, :light}
      assert Board.get(game_after_first.board, 1, 9) == {:marked, :light}

      # Move scanner back to position 0 for second sweep
      second_state = %{game_after_first | scanner: %Scanner{position: 0.0, speed: 2.0}}
      inject_game_state(view, second_state)

      # Second sweep: clears the chain-reaction light marks
      send(view.pid, :scanner_tick)
      _ = render(view)

      game_after_second = game_state(view)

      # All tiles should be gone now
      assert Board.get(game_after_second.board, 0, 8) == nil
      assert Board.get(game_after_second.board, 1, 8) == nil
      assert Board.get(game_after_second.board, 0, 9) == nil
      assert Board.get(game_after_second.board, 1, 9) == nil

      # Score should have increased from second clear too
      assert game_after_second.score > game_after_first.score
    end
  end

  # ── Player Movement via LiveView Events ─────────────────────────────

  describe "player input through LiveView events" do
    test "ArrowLeft moves piece left", %{conn: conn} do
      view = start_game(conn)

      state =
        build_playing_state(piece: %Piece{cells: {:dark, :dark, :dark, :dark}, col: 10, row: 3})

      inject_game_state(view, state)

      render_keydown(view, "keydown", %{"key" => "ArrowLeft"})

      game = game_state(view)
      assert game.active_piece.col == 9
    end

    test "ArrowRight moves piece right", %{conn: conn} do
      view = start_game(conn)

      state =
        build_playing_state(piece: %Piece{cells: {:dark, :dark, :dark, :dark}, col: 10, row: 3})

      inject_game_state(view, state)

      render_keydown(view, "keydown", %{"key" => "ArrowRight"})

      game = game_state(view)
      assert game.active_piece.col == 11
    end

    test "ArrowLeft against left wall does nothing", %{conn: conn} do
      view = start_game(conn)

      state =
        build_playing_state(piece: %Piece{cells: {:dark, :dark, :dark, :dark}, col: 0, row: 3})

      inject_game_state(view, state)

      render_keydown(view, "keydown", %{"key" => "ArrowLeft"})

      game = game_state(view)
      assert game.active_piece.col == 0
    end

    test "ArrowRight against right wall does nothing", %{conn: conn} do
      view = start_game(conn)

      # Board width 24, piece is 2 wide, so col 22 means cols 22-23
      state =
        build_playing_state(piece: %Piece{cells: {:dark, :dark, :dark, :dark}, col: 22, row: 3})

      inject_game_state(view, state)

      render_keydown(view, "keydown", %{"key" => "ArrowRight"})

      game = game_state(view)
      assert game.active_piece.col == 22
    end

    test "ArrowUp rotates piece clockwise", %{conn: conn} do
      view = start_game(conn)

      state =
        build_playing_state(piece: %Piece{cells: {:dark, :light, :light, :dark}, col: 10, row: 3})

      inject_game_state(view, state)

      render_keydown(view, "keydown", %{"key" => "ArrowUp"})

      game = game_state(view)
      # CW rotation of {tl, tr, bl, br} = {bl, tl, br, tr}
      # {dark, light, light, dark} -> {light, dark, dark, light}
      assert game.active_piece.cells == {:light, :dark, :dark, :light}
    end

    test "z rotates piece counter-clockwise", %{conn: conn} do
      view = start_game(conn)

      state =
        build_playing_state(piece: %Piece{cells: {:dark, :light, :light, :dark}, col: 10, row: 3})

      inject_game_state(view, state)

      render_keydown(view, "keydown", %{"key" => "z"})

      game = game_state(view)
      # CCW rotation of {tl, tr, bl, br} = {tr, br, tl, bl}
      # {dark, light, light, dark} -> {light, dark, dark, light}
      assert game.active_piece.cells == {:light, :dark, :dark, :light}
    end

    test "soft drop moves piece down one row", %{conn: conn} do
      view = start_game(conn)

      state =
        build_playing_state(piece: %Piece{cells: {:dark, :dark, :dark, :dark}, col: 10, row: 3})

      inject_game_state(view, state)

      render_keydown(view, "keydown", %{"key" => "ArrowDown"})

      game = game_state(view)
      assert game.active_piece.row == 4
    end

    test "keyboard input is ignored when game is not playing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/play")
      # Game is in :waiting phase

      render_keydown(view, "keydown", %{"key" => "ArrowLeft"})
      render_keydown(view, "keydown", %{"key" => " "})

      game = game_state(view)
      assert game.phase == :waiting
    end
  end

  # ── Game Over ───────────────────────────────────────────────────────

  describe "game over detection" do
    test "game over when piece locks in row 0", %{conn: conn} do
      view = start_game(conn)

      # Fill board high enough that the next piece can't fit.
      # Put tiles in rows 1-9 across piece spawn columns (11-12)
      board =
        Enum.reduce(1..9, Board.new(), fn row, b ->
          b
          |> Board.put(11, row, :dark)
          |> Board.put(12, row, :dark)
        end)

      # Piece at row 0 — gravity tick will try row 1, collision, lock at row 0
      # Board.topped_out? checks row 0
      state =
        build_playing_state(
          board: board,
          piece: %Piece{cells: {:dark, :dark, :dark, :dark}, col: 11, row: 0}
        )

      inject_game_state(view, state)

      # Gravity tick causes lock at row 0 → game over
      send(view.pid, :gravity_tick)
      _ = render(view)

      game = game_state(view)
      assert game.phase == :game_over
      assert game.active_piece == nil
    end

    test "game over shows game-over overlay", %{conn: conn} do
      view = start_game(conn)

      board =
        Enum.reduce(1..9, Board.new(), fn row, b ->
          b |> Board.put(11, row, :dark) |> Board.put(12, row, :dark)
        end)

      state =
        build_playing_state(
          board: board,
          piece: %Piece{cells: {:dark, :dark, :dark, :dark}, col: 11, row: 0}
        )

      inject_game_state(view, state)

      send(view.pid, :gravity_tick)
      _ = render(view)

      assert has_element?(view, "#game-over")
      assert has_element?(view, "#restart-btn")
    end

    test "timers stop on game over", %{conn: conn} do
      view = start_game(conn)

      board =
        Enum.reduce(1..9, Board.new(), fn row, b ->
          b |> Board.put(11, row, :dark) |> Board.put(12, row, :dark)
        end)

      state =
        build_playing_state(
          board: board,
          piece: %Piece{cells: {:dark, :dark, :dark, :dark}, col: 11, row: 0}
        )

      inject_game_state(view, state)

      send(view.pid, :gravity_tick)
      _ = render(view)

      # Verify the LiveView state has nil timer refs (timers cancelled)
      lv_state = :sys.get_state(view.pid)
      assigns = get_in(lv_state, [Access.key(:socket), Access.key(:assigns)])
      assert assigns.gravity_ref == nil
      assert assigns.scanner_ref == nil
    end
  end

  # ── Restart ─────────────────────────────────────────────────────────

  describe "restart from game over" do
    test "restart resets game to playing state", %{conn: conn} do
      view = start_game(conn)

      # Force game over
      board =
        Enum.reduce(1..9, Board.new(), fn row, b ->
          b |> Board.put(11, row, :dark) |> Board.put(12, row, :dark)
        end)

      state =
        build_playing_state(
          board: board,
          piece: %Piece{cells: {:dark, :dark, :dark, :dark}, col: 11, row: 0},
          score: 500
        )

      inject_game_state(view, state)

      send(view.pid, :gravity_tick)
      _ = render(view)

      assert game_state(view).phase == :game_over

      # Click restart
      view |> element("#restart-btn") |> render_click()

      game = game_state(view)
      assert game.phase == :playing
      assert game.score == 0
      assert game.level == 1
      assert game.active_piece != nil
      assert game.active_piece.row == 0

      refute has_element?(view, "#game-over")
    end
  end

  # ── Queue Management ────────────────────────────────────────────────

  describe "queue management through play" do
    test "queue cycles as pieces lock", %{conn: conn} do
      view = start_game(conn)

      queue_piece_1 = %Piece{cells: {:light, :light, :light, :light}, col: 11, row: 0}
      queue_piece_2 = %Piece{cells: {:dark, :light, :light, :dark}, col: 11, row: 0}
      queue_piece_3 = %Piece{cells: {:light, :dark, :dark, :light}, col: 11, row: 0}

      state =
        build_playing_state(
          piece: %Piece{cells: {:dark, :dark, :dark, :dark}, col: 5, row: 0},
          queue: [queue_piece_1, queue_piece_2, queue_piece_3]
        )

      inject_game_state(view, state)

      # Hard drop current piece
      render_keydown(view, "keydown", %{"key" => " "})

      game = game_state(view)

      # Next piece should be the first from queue
      assert game.active_piece.cells == {:light, :light, :light, :light}

      # Queue should still have 3 pieces (2 remaining + 1 new random)
      assert length(game.queue) == 3
      # Second in original queue is now first
      assert Enum.at(game.queue, 0).cells == {:dark, :light, :light, :dark}
      assert Enum.at(game.queue, 1).cells == {:light, :dark, :dark, :light}
    end
  end

  # ── Level Up ────────────────────────────────────────────────────────

  describe "level progression" do
    test "reaching 50 lines cleared triggers level up", %{conn: conn} do
      view = start_game(conn)

      # Set up state just below the level-up threshold
      # 4 marked tiles + lines_cleared 46 = 50 after clear
      board =
        Board.new()
        |> Board.put(0, 8, {:marked, :dark})
        |> Board.put(1, 8, {:marked, :dark})
        |> Board.put(0, 9, {:marked, :dark})
        |> Board.put(1, 9, {:marked, :dark})

      state =
        build_playing_state(
          board: board,
          scanner: %Scanner{position: 0.0, speed: 2.0},
          lines_cleared: 46,
          level: 1,
          gravity_interval: 1000,
          piece: %Piece{cells: {:dark, :light, :light, :dark}, col: 11, row: 0}
        )

      inject_game_state(view, state)

      send(view.pid, :scanner_tick)
      _ = render(view)

      game = game_state(view)

      assert game.lines_cleared == 50
      assert game.level == 2
      assert game.gravity_interval == 900
    end

    test "level up at higher levels decreases gravity interval further", %{conn: conn} do
      view = start_game(conn)

      board =
        Board.new()
        |> Board.put(0, 8, {:marked, :dark})
        |> Board.put(1, 8, {:marked, :dark})
        |> Board.put(0, 9, {:marked, :dark})
        |> Board.put(1, 9, {:marked, :dark})

      state =
        build_playing_state(
          board: board,
          scanner: %Scanner{position: 0.0, speed: 2.0},
          lines_cleared: 96,
          level: 2,
          gravity_interval: 900,
          piece: %Piece{cells: {:dark, :light, :light, :dark}, col: 11, row: 0}
        )

      inject_game_state(view, state)

      send(view.pid, :scanner_tick)
      _ = render(view)

      game = game_state(view)

      assert game.lines_cleared == 100
      assert game.level == 3
      assert game.gravity_interval == 800
    end

    test "gravity interval cannot go below 100ms", %{conn: conn} do
      view = start_game(conn)

      board =
        Board.new()
        |> Board.put(0, 8, {:marked, :dark})
        |> Board.put(1, 8, {:marked, :dark})
        |> Board.put(0, 9, {:marked, :dark})
        |> Board.put(1, 9, {:marked, :dark})

      state =
        build_playing_state(
          board: board,
          scanner: %Scanner{position: 0.0, speed: 2.0},
          lines_cleared: 496,
          level: 10,
          gravity_interval: 100,
          piece: %Piece{cells: {:dark, :light, :light, :dark}, col: 11, row: 0}
        )

      inject_game_state(view, state)

      send(view.pid, :scanner_tick)
      _ = render(view)

      game = game_state(view)

      assert game.level == 11
      # Should not go below 100
      assert game.gravity_interval == 100
    end
  end

  # ── Score Accumulation ──────────────────────────────────────────────

  describe "score calculation" do
    test "score scales with level", %{conn: conn} do
      view = start_game(conn)

      board =
        Board.new()
        |> Board.put(0, 8, {:marked, :dark})
        |> Board.put(1, 8, {:marked, :dark})
        |> Board.put(0, 9, {:marked, :dark})
        |> Board.put(1, 9, {:marked, :dark})

      state =
        build_playing_state(
          board: board,
          scanner: %Scanner{position: 0.0, speed: 2.0},
          score: 0,
          level: 3,
          piece: %Piece{cells: {:dark, :light, :light, :dark}, col: 11, row: 0}
        )

      inject_game_state(view, state)

      send(view.pid, :scanner_tick)
      _ = render(view)

      game = game_state(view)

      # 4 tiles * 10 * level 3 = 120
      assert game.score == 120
    end

    test "score accumulates across multiple clears", %{conn: conn} do
      view = start_game(conn)

      board =
        Board.new()
        |> Board.put(0, 8, {:marked, :dark})
        |> Board.put(1, 8, {:marked, :dark})
        |> Board.put(0, 9, {:marked, :dark})
        |> Board.put(1, 9, {:marked, :dark})

      state =
        build_playing_state(
          board: board,
          scanner: %Scanner{position: 0.0, speed: 2.0},
          score: 100,
          level: 1,
          piece: %Piece{cells: {:dark, :light, :light, :dark}, col: 11, row: 0}
        )

      inject_game_state(view, state)

      send(view.pid, :scanner_tick)
      _ = render(view)

      game = game_state(view)

      # Starting 100 + (4 * 10 * 1) = 140
      assert game.score == 140
    end
  end

  # ── Scanner Wrapping ────────────────────────────────────────────────

  describe "scanner wrapping at board edge" do
    test "scanner wraps from end of board back to start", %{conn: conn} do
      view = start_game(conn)

      # Position scanner near end of board (width 24)
      state =
        build_playing_state(
          scanner: %Scanner{position: 23.5, speed: 1.0},
          piece: %Piece{cells: {:dark, :dark, :dark, :dark}, col: 11, row: 0}
        )

      inject_game_state(view, state)

      send(view.pid, :scanner_tick)
      _ = render(view)

      game = game_state(view)

      # Should have wrapped — new position should be 0.5 (24.5 - 24)
      assert game.scanner.position == 0.5
    end

    test "scanner clears marked tiles during wrap", %{conn: conn} do
      view = start_game(conn)

      # Marked tiles at column 23 (last column)
      board =
        Board.new()
        |> Board.put(23, 8, {:marked, :dark})
        |> Board.put(23, 9, {:marked, :dark})

      state =
        build_playing_state(
          board: board,
          scanner: %Scanner{position: 23.0, speed: 1.5},
          piece: %Piece{cells: {:dark, :light, :light, :dark}, col: 11, row: 0}
        )

      inject_game_state(view, state)

      send(view.pid, :scanner_tick)
      _ = render(view)

      game = game_state(view)

      # Column 23 marks should be cleared
      assert Board.get(game.board, 23, 8) == nil
      assert Board.get(game.board, 23, 9) == nil
    end
  end

  # ── Full Play Scenario ──────────────────────────────────────────────

  describe "full play scenario" do
    test "place piece, get marked, scanner clears, score updates, new piece spawns", %{conn: conn} do
      view = start_game(conn)

      next_piece = %Piece{cells: {:light, :light, :light, :light}, col: 11, row: 0}

      # Start with empty board, all-dark piece about to land
      state =
        build_playing_state(
          piece: %Piece{cells: {:dark, :dark, :dark, :dark}, col: 5, row: 0},
          scanner: %Scanner{position: 0.0, speed: 0.0625},
          queue: [
            next_piece,
            %Piece{cells: {:dark, :light, :light, :dark}, col: 11, row: 0},
            %Piece{cells: {:light, :dark, :dark, :light}, col: 11, row: 0}
          ]
        )

      inject_game_state(view, state)

      # 1. Hard drop — piece lands at bottom, forms 2x2 dark match
      render_keydown(view, "keydown", %{"key" => " "})

      game = game_state(view)
      assert Board.get(game.board, 5, 8) == {:marked, :dark}
      assert game.active_piece != nil
      # Next piece is first from queue
      assert game.active_piece.cells == {:light, :light, :light, :light}

      # 2. Advance scanner to column 5 to clear the marks
      advanced_state = %{game | scanner: %Scanner{position: 5.0, speed: 2.0}}
      inject_game_state(view, advanced_state)

      send(view.pid, :scanner_tick)
      _ = render(view)

      final = game_state(view)

      # Marked tiles at cols 5-6 should be cleared
      assert Board.get(final.board, 5, 8) == nil
      assert Board.get(final.board, 6, 8) == nil
      assert Board.get(final.board, 5, 9) == nil
      assert Board.get(final.board, 6, 9) == nil

      # Score should reflect the clear
      assert final.score > 0
    end
  end

  # ── Concurrent Timer Behavior ───────────────────────────────────────

  describe "gravity and scanner timer interleaving" do
    test "gravity and scanner ticks interleave correctly", %{conn: conn} do
      view = start_game(conn)

      state =
        build_playing_state(
          piece: %Piece{cells: {:dark, :dark, :dark, :dark}, col: 5, row: 2},
          scanner: %Scanner{position: 10.0, speed: 0.5}
        )

      inject_game_state(view, state)

      # Interleave: gravity, scanner, gravity, scanner
      send(view.pid, :gravity_tick)
      _ = render(view)
      game1 = game_state(view)
      assert game1.active_piece.row == 3

      send(view.pid, :scanner_tick)
      _ = render(view)
      game2 = game_state(view)
      assert game2.scanner.position > 10.0

      send(view.pid, :gravity_tick)
      _ = render(view)
      game3 = game_state(view)
      assert game3.active_piece.row == 4

      send(view.pid, :scanner_tick)
      _ = render(view)
      game4 = game_state(view)
      assert game4.scanner.position > game2.scanner.position
    end
  end
end
