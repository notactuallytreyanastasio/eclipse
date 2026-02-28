defmodule IlluminatesWeb.EclipseLive do
  @moduledoc """
  LiveView for the Eclipse game — a falling-block puzzle with a Game Boy DMG aesthetic.
  """

  use IlluminatesWeb, :live_view

  alias Illuminates.Eclipse.Board
  alias Illuminates.Eclipse.Game
  alias Illuminates.Eclipse.Piece

  @impl true
  def mount(_params, _session, socket) do
    game = Game.new_game()

    socket =
      socket
      |> assign(:game, game)
      |> assign(:gravity_ref, nil)
      |> assign(:scanner_ref, nil)
      |> assign(:page_title, "Eclipse")

    {:ok, socket}
  end

  @impl true
  def handle_event("start_game", _params, socket) do
    game = socket.assigns.game |> Game.start()

    socket =
      socket
      |> assign(:game, game)
      |> schedule_gravity()
      |> schedule_scanner()

    {:noreply, socket}
  end

  def handle_event("restart", _params, socket) do
    game = Game.new_game() |> Game.start()

    socket =
      socket
      |> cancel_timers()
      |> assign(:game, game)
      |> schedule_gravity()
      |> schedule_scanner()

    {:noreply, socket}
  end

  def handle_event("keydown", _params, %{assigns: %{game: %{phase: phase}}} = socket)
      when phase != :playing do
    {:noreply, socket}
  end

  def handle_event("keydown", %{"key" => "ArrowLeft"}, socket) do
    {:noreply, update_game(socket, &Game.move_left/1)}
  end

  def handle_event("keydown", %{"key" => "ArrowRight"}, socket) do
    {:noreply, update_game(socket, &Game.move_right/1)}
  end

  def handle_event("keydown", %{"key" => "ArrowDown"}, socket) do
    {:noreply, update_game(socket, &Game.soft_drop/1)}
  end

  def handle_event("keydown", %{"key" => "ArrowUp"}, socket) do
    {:noreply, update_game(socket, &Game.rotate_cw/1)}
  end

  def handle_event("keydown", %{"key" => "z"}, socket) do
    {:noreply, update_game(socket, &Game.rotate_ccw/1)}
  end

  def handle_event("keydown", %{"key" => " "}, socket) do
    {:noreply, update_game(socket, &Game.hard_drop/1)}
  end

  def handle_event("keydown", _key, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:gravity_tick, socket) do
    {:noreply, handle_tick(socket, &Game.gravity_tick/1, &schedule_gravity/1)}
  end

  def handle_info(:scanner_tick, socket) do
    {:noreply, handle_tick(socket, &Game.scanner_tick/1, &schedule_scanner/1)}
  end

  # --- Helpers ---

  defp handle_tick(socket, game_fn, schedule_fn) do
    game = game_fn.(socket.assigns.game)
    socket = assign(socket, :game, game)

    if game.phase == :game_over do
      cancel_timers(socket)
    else
      schedule_fn.(socket)
    end
  end

  defp update_game(socket, fun) do
    assign(socket, :game, fun.(socket.assigns.game))
  end

  defp schedule_gravity(socket) do
    if socket.assigns.gravity_ref, do: Process.cancel_timer(socket.assigns.gravity_ref)
    ref = Process.send_after(self(), :gravity_tick, socket.assigns.game.gravity_interval)
    assign(socket, :gravity_ref, ref)
  end

  defp schedule_scanner(socket) do
    if socket.assigns.scanner_ref, do: Process.cancel_timer(socket.assigns.scanner_ref)
    ref = Process.send_after(self(), :scanner_tick, socket.assigns.game.scanner_interval)
    assign(socket, :scanner_ref, ref)
  end

  defp cancel_timers(socket) do
    if socket.assigns.gravity_ref, do: Process.cancel_timer(socket.assigns.gravity_ref)
    if socket.assigns.scanner_ref, do: Process.cancel_timer(socket.assigns.scanner_ref)
    assign(socket, gravity_ref: nil, scanner_ref: nil)
  end

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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div
        id="eclipse-game"
        class="flex flex-col items-center gap-6 min-h-screen py-8"
        phx-window-keydown="keydown"
      >
        <%!-- Title --%>
        <h1 class="eclipse-text text-2xl tracking-[0.3em]">ECLIPSE</h1>

        <%!-- HUD --%>
        <div id="game-hud" class="flex gap-8 eclipse-text text-sm">
          <div>SCORE {String.pad_leading(Integer.to_string(@game.score), 8, "0")}</div>
          <div>LEVEL {String.pad_leading(Integer.to_string(@game.level), 2, "0")}</div>
        </div>

        <div class="flex gap-6 items-start">
          <%!-- Main board with screen bezel --%>
          <div class="eclipse-screen">
            <div id="game-board" class="eclipse-board relative">
              <%!-- Scanner line --%>
              <%= if @game.phase == :playing do %>
                <div
                  id="scanner-line"
                  class="eclipse-scanner"
                  style={"left: #{scanner_left_pct(@game.scanner, @game.board.width)}%"}
                >
                </div>
              <% end %>

              <%!-- Grid cells --%>
              <%= for row <- 0..(@game.board.height - 1) do %>
                <%= for col <- 0..(@game.board.width - 1) do %>
                  <div
                    id={"cell-#{col}-#{row}"}
                    class={cell_class(@game.board, @game.active_piece, col, row)}
                  >
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>

          <%!-- Side panel --%>
          <div id="queue-panel" class="flex flex-col gap-3">
            <div class="eclipse-text text-xs">NEXT</div>
            <%= for {piece, idx} <- Enum.with_index(@game.queue) do %>
              <div id={"queue-#{idx}"} class="eclipse-preview">
                <%= for qrow <- 0..1 do %>
                  <%= for qcol <- 0..1 do %>
                    <div class={queue_cell_class(piece, qcol, qrow)}></div>
                  <% end %>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Controls hint --%>
        <div class="eclipse-text text-xs opacity-60 tracking-wider">
          ARROWS MOVE / UP ROTATE / SPACE DROP
        </div>

        <%!-- Overlays --%>
        <%= if @game.phase == :waiting do %>
          <button id="start-btn" class="eclipse-start-btn" phx-click="start_game">
            PRESS START
          </button>
        <% end %>

        <%= if @game.phase == :game_over do %>
          <div id="game-over" class="flex flex-col items-center gap-4">
            <div class="eclipse-game-over eclipse-text text-xl">GAME OVER</div>
            <div class="eclipse-text text-sm">
              FINAL SCORE {String.pad_leading(Integer.to_string(@game.score), 8, "0")}
            </div>
            <button id="restart-btn" class="eclipse-start-btn" phx-click="restart">
              PLAY AGAIN
            </button>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
