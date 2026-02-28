defmodule EclipseWeb.GameComponents do
  @moduledoc """
  Function components for the Eclipse game UI.
  """

  use Phoenix.Component

  alias Eclipse.Game.Board
  alias Eclipse.Game.Piece

  attr :score, :integer, required: true
  attr :level, :integer, required: true
  attr :total_squares_cleared, :integer, required: true

  def game_hud(assigns) do
    assigns = assign(assigns, :progress, rem(assigns.total_squares_cleared, 50))

    ~H"""
    <div id="game-hud" class="flex gap-8 eclipse-text text-sm">
      <div>SCORE {String.pad_leading(Integer.to_string(@score), 8, "0")}</div>
      <div>LEVEL {String.pad_leading(Integer.to_string(@level), 2, "0")}</div>
      <div>PROGRESS {String.pad_leading(Integer.to_string(@progress), 2, "0")}/50</div>
    </div>
    """
  end

  attr :board, :map, required: true
  attr :active_piece, :any, required: true
  attr :scanner, :map, required: true
  attr :phase, :atom, required: true

  def game_board(assigns) do
    ~H"""
    <div class="eclipse-screen">
      <div id="game-board" class="eclipse-board relative">
        <%= if @phase == :playing do %>
          <div
            id="scanner-line"
            class="eclipse-scanner"
            style={"left: #{scanner_left_pct(@scanner, @board.width)}%"}
          >
          </div>
        <% end %>

        <%= for row <- 0..(@board.height - 1) do %>
          <%= for col <- 0..(@board.width - 1) do %>
            <div
              id={"cell-#{col}-#{row}"}
              class={cell_class(@board, @active_piece, col, row)}
            >
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  attr :queue, :list, required: true

  def queue_panel(assigns) do
    ~H"""
    <div id="queue-panel" class="flex flex-col gap-3">
      <div class="eclipse-text text-xs">NEXT</div>
      <%= for {piece, idx} <- Enum.with_index(@queue) do %>
        <div id={"queue-#{idx}"} class="eclipse-preview">
          <%= for qrow <- 0..1 do %>
            <%= for qcol <- 0..1 do %>
              <div class={queue_cell_class(piece, qcol, qrow)}></div>
            <% end %>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  def game_controls(assigns) do
    ~H"""
    <div class="eclipse-text text-xs opacity-60 tracking-wider">
      ARROWS MOVE / UP ROTATE / SPACE DROP
    </div>
    """
  end

  def start_overlay(assigns) do
    ~H"""
    <button id="start-btn" class="eclipse-start-btn" phx-click="start_game">
      PRESS START
    </button>
    """
  end

  attr :score, :integer, required: true

  def game_over_overlay(assigns) do
    ~H"""
    <div id="game-over" class="flex flex-col items-center gap-4">
      <div class="eclipse-game-over eclipse-text text-xl">GAME OVER</div>
      <div class="eclipse-text text-sm">
        FINAL SCORE {String.pad_leading(Integer.to_string(@score), 8, "0")}
      </div>
      <button id="restart-btn" class="eclipse-start-btn" phx-click="restart">
        PLAY AGAIN
      </button>
    </div>
    """
  end

  # --- Private helpers ---

  defp cell_class(board, active_piece, col, row) do
    active = active_piece_at(active_piece, col, row)
    board_cell = Board.get(board, col, row)
    cell = active || board_cell

    color_class =
      case cell do
        nil -> "eclipse-empty"
        :dark -> "eclipse-dark"
        :light -> "eclipse-light"
        {:marked, :dark} -> "eclipse-marked-dark"
        {:marked, :light} -> "eclipse-marked-light"
        {:active, :dark} -> "eclipse-dark eclipse-active"
        {:active, :light} -> "eclipse-light eclipse-active"
      end

    "eclipse-cell #{color_class}"
  end

  defp active_piece_at(nil, _col, _row), do: nil

  defp active_piece_at(piece, col, row) do
    Piece.cells_positions(piece)
    |> Enum.find_value(fn {pc, pr, color} ->
      if pc == col and pr == row, do: {:active, color}
    end)
  end

  defp scanner_left_pct(scanner, board_width) do
    scanner.position / board_width * 100
  end

  defp queue_cell_class(piece, col, row) do
    {tl, tr, bl, br} = piece.cells

    color =
      case {col, row} do
        {0, 0} -> tl
        {1, 0} -> tr
        {0, 1} -> bl
        {1, 1} -> br
      end

    case color do
      :dark -> "eclipse-cell eclipse-dark"
      :light -> "eclipse-cell eclipse-light"
    end
  end
end
