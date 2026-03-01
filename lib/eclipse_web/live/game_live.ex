defmodule EclipseWeb.GameLive do
  @moduledoc """
  LiveView for the Eclipse game — a falling-block puzzle with a Game Boy DMG aesthetic.
  """

  use EclipseWeb, :live_view

  import EclipseWeb.GameComponents

  alias Eclipse.Game.Engine

  @initial_move_interval 150
  @min_move_interval 30
  @move_acceleration 15

  @impl true
  def mount(_params, _session, socket) do
    game = Engine.new_game()

    socket =
      socket
      |> assign(:game, game)
      |> assign(:gravity_ref, nil)
      |> assign(:scanner_ref, nil)
      |> assign(:page_title, "Eclipse")
      |> assign(:held_keys, MapSet.new())
      |> assign(:move_timer_ref, nil)
      |> assign(:move_interval, @initial_move_interval)

    {:ok, socket}
  end

  @impl true
  def handle_event("start_game", _params, socket) do
    game = socket.assigns.game |> Engine.start()

    socket =
      socket
      |> assign(:game, game)
      |> schedule_gravity()
      |> schedule_scanner()

    {:noreply, socket}
  end

  def handle_event("restart", _params, socket) do
    game = Engine.new_game() |> Engine.start()

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

  def handle_event("keydown", %{"key" => key}, socket) when key in ["ArrowLeft", "ArrowRight"] do
    if MapSet.member?(socket.assigns.held_keys, key) do
      {:noreply, socket}
    else
      socket =
        socket
        |> handle_directional_input(key)
        |> assign(:held_keys, MapSet.put(socket.assigns.held_keys, key))
        |> start_move_timer()

      {:noreply, socket}
    end
  end

  def handle_event("keydown", %{"key" => "ArrowDown"}, socket) do
    {:noreply, update_game(socket, &Engine.soft_drop/1)}
  end

  def handle_event("keydown", %{"key" => "ArrowUp"}, socket) do
    {:noreply, update_game(socket, &Engine.rotate_cw/1)}
  end

  def handle_event("keydown", %{"key" => "z"}, socket) do
    {:noreply, update_game(socket, &Engine.rotate_ccw/1)}
  end

  def handle_event("keydown", %{"key" => " "}, socket) do
    {:noreply, update_game(socket, &Engine.hard_drop/1)}
  end

  def handle_event("keydown", _key, socket), do: {:noreply, socket}

  def handle_event("keyup", %{"key" => key}, socket) when key in ["ArrowLeft", "ArrowRight"] do
    held_keys = MapSet.delete(socket.assigns.held_keys, key)
    socket = assign(socket, :held_keys, held_keys)

    socket =
      if MapSet.size(held_keys) == 0 do
        cancel_move_timer(socket)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("keyup", _key, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:gravity_tick, socket) do
    {:noreply, handle_tick(socket, &Engine.gravity_tick/1, &schedule_gravity/1)}
  end

  def handle_info(:scanner_tick, socket) do
    {:noreply, handle_tick(socket, &Engine.scanner_tick/1, &schedule_scanner/1)}
  end

  def handle_info(:move_tick, socket) do
    socket =
      Enum.reduce(socket.assigns.held_keys, socket, fn key, acc ->
        handle_directional_input(acc, key)
      end)

    # Accelerate: reduce interval each tick (min 30ms for super fast movement)
    new_interval = max(@min_move_interval, socket.assigns.move_interval - @move_acceleration)

    socket =
      socket
      |> assign(:move_interval, new_interval)
      |> schedule_move_tick()

    {:noreply, socket}
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
    if socket.assigns.move_timer_ref, do: Process.cancel_timer(socket.assigns.move_timer_ref)

    assign(socket,
      gravity_ref: nil,
      scanner_ref: nil,
      move_timer_ref: nil,
      held_keys: MapSet.new(),
      move_interval: @initial_move_interval
    )
  end

  defp handle_directional_input(socket, "ArrowLeft") do
    update_game(socket, &Engine.move_left/1)
  end

  defp handle_directional_input(socket, "ArrowRight") do
    update_game(socket, &Engine.move_right/1)
  end

  defp start_move_timer(socket) do
    if socket.assigns.move_timer_ref do
      socket
    else
      socket
      |> assign(:move_interval, @initial_move_interval)
      |> schedule_move_tick()
    end
  end

  defp schedule_move_tick(socket) do
    if socket.assigns.move_timer_ref, do: Process.cancel_timer(socket.assigns.move_timer_ref)
    ref = Process.send_after(self(), :move_tick, socket.assigns.move_interval)
    assign(socket, :move_timer_ref, ref)
  end

  defp cancel_move_timer(socket) do
    if socket.assigns.move_timer_ref, do: Process.cancel_timer(socket.assigns.move_timer_ref)
    assign(socket, move_timer_ref: nil, move_interval: @initial_move_interval)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div
        id="eclipse-game"
        class="flex flex-col items-center gap-6 min-h-screen py-8"
        phx-window-keydown="keydown"
        phx-window-keyup="keyup"
        phx-hook=".PreventScroll"
      >
        <script :type={Phoenix.LiveView.ColocatedHook} name=".PreventScroll">
          export default {
            mounted() {
              const gameKeys = new Set(["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", " "]);
              this.handler = (e) => {
                if (gameKeys.has(e.key)) { e.preventDefault(); }
              };
              window.addEventListener("keydown", this.handler);
            },
            destroyed() {
              window.removeEventListener("keydown", this.handler);
            }
          }
        </script>

        <h1 class="eclipse-text text-2xl tracking-[0.3em]">ECLIPSE</h1>

        <.game_hud
          score={@game.score}
          level={@game.level}
          total_squares_cleared={@game.total_squares_cleared}
        />

        <div class="flex gap-6 items-start">
          <.game_board
            board={@game.board}
            active_piece={@game.active_piece}
            scanner={@game.scanner}
            phase={@game.phase}
          />
          <.queue_panel queue={@game.queue} />
        </div>

        <.game_controls />
        <.start_overlay :if={@game.phase == :waiting} />
        <.game_over_overlay :if={@game.phase == :game_over} score={@game.score} />
      </div>
    </Layouts.app>
    """
  end
end
