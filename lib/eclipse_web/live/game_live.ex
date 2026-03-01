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
    session_id = generate_session_id()

    socket =
      assign(socket,
        game: game,
        session_id: session_id,
        gravity_ref: nil,
        scanner_ref: nil,
        page_title: "Eclipse",
        held_keys: MapSet.new(),
        move_timer_ref: nil,
        move_interval: @initial_move_interval
      )

    socket =
      if connected?(socket) do
        subscribe_to_topics(socket)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("start_game", _params, socket) do
    game = Engine.start(socket.assigns.game)

    socket =
      socket
      |> assign(:game, game)
      |> schedule_gravity()
      |> schedule_scanner()

    {:noreply, socket}
  end

  @impl true
  def handle_event("restart", _params, socket) do
    game = Engine.start(Engine.new_game())

    socket =
      socket
      |> cancel_timers()
      |> assign(:game, game)
      |> schedule_gravity()
      |> schedule_scanner()

    {:noreply, socket}
  end

  @impl true
  def handle_event("keydown", _params, %{assigns: %{game: %{phase: :waiting}}} = socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("keydown", _params, %{assigns: %{game: %{phase: :game_over}}} = socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("keydown", %{"key" => key}, socket) when key in ["ArrowLeft", "ArrowRight"] do
    case MapSet.member?(socket.assigns.held_keys, key) do
      true ->
        {:noreply, socket}

      false ->
        held_keys = MapSet.put(socket.assigns.held_keys, key)

        socket =
          socket
          |> handle_directional_input(key)
          |> assign(:held_keys, held_keys)
          |> start_move_timer()

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("keydown", %{"key" => "ArrowDown"}, socket) do
    {:noreply, update_game(socket, &Engine.soft_drop/1)}
  end

  @impl true
  def handle_event("keydown", %{"key" => "ArrowUp"}, socket) do
    {:noreply, update_game(socket, &Engine.rotate_cw/1)}
  end

  @impl true
  def handle_event("keydown", %{"key" => "z"}, socket) do
    {:noreply, update_game(socket, &Engine.rotate_ccw/1)}
  end

  @impl true
  def handle_event("keydown", %{"key" => " "}, socket) do
    {:noreply, update_game(socket, &Engine.hard_drop/1)}
  end

  @impl true
  def handle_event("keydown", _key, socket), do: {:noreply, socket}

  @impl true
  def handle_event("keyup", %{"key" => key}, socket) when key in ["ArrowLeft", "ArrowRight"] do
    held_keys = MapSet.delete(socket.assigns.held_keys, key)

    socket =
      socket
      |> assign(:held_keys, held_keys)
      |> maybe_cancel_move_timer(held_keys)

    {:noreply, socket}
  end

  @impl true
  def handle_event("keyup", _key, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:broadcast_tick, topic}, socket) do
    Phoenix.PubSub.broadcast(Eclipse.PubSub, topic, %{topic: topic, event: "tick"})
    {:noreply, socket}
  end

  @impl true
  def handle_info(%{topic: topic, event: "tick"}, socket) do
    {:noreply, handle_tick_by_topic(socket, topic)}
  end

  # Backward compatibility for direct message sends (used in tests)
  @impl true
  def handle_info(:gravity_tick, socket) do
    {:noreply, handle_tick(socket, &Engine.gravity_tick/1, &schedule_gravity/1)}
  end

  @impl true
  def handle_info(:scanner_tick, socket) do
    {:noreply, handle_tick(socket, &Engine.scanner_tick/1, &schedule_scanner/1)}
  end

  @impl true
  def handle_info(:move_tick, socket) do
    {:noreply, handle_move_tick(socket)}
  end

  # --- Helpers ---

  defp handle_tick_by_topic(%{assigns: %{session_id: sid}} = socket, topic) do
    gravity = gravity_topic(sid)
    scanner = scanner_topic(sid)
    move = move_topic(sid)

    case topic do
      ^gravity -> handle_tick(socket, &Engine.gravity_tick/1, &schedule_gravity/1)
      ^scanner -> handle_tick(socket, &Engine.scanner_tick/1, &schedule_scanner/1)
      ^move -> handle_move_tick(socket)
      _ -> socket
    end
  end

  defp handle_move_tick(socket) do
    socket =
      Enum.reduce(socket.assigns.held_keys, socket, fn key, acc ->
        handle_directional_input(acc, key)
      end)

    new_interval = max(@min_move_interval, socket.assigns.move_interval - @move_acceleration)

    socket
    |> assign(:move_interval, new_interval)
    |> schedule_move_tick()
  end

  defp handle_tick(socket, game_fn, schedule_fn) do
    game = game_fn.(socket.assigns.game)
    socket = assign(socket, :game, game)

    case game.phase do
      :game_over -> cancel_timers(socket)
      _playing -> schedule_fn.(socket)
    end
  end

  defp update_game(socket, fun) do
    assign(socket, :game, fun.(socket.assigns.game))
  end

  defp schedule_gravity(socket) do
    socket
    |> cancel_timer(:gravity_ref)
    |> broadcast_after(
      :gravity_ref,
      gravity_topic(socket.assigns.session_id),
      socket.assigns.game.gravity_interval
    )
  end

  defp schedule_scanner(socket) do
    socket
    |> cancel_timer(:scanner_ref)
    |> broadcast_after(
      :scanner_ref,
      scanner_topic(socket.assigns.session_id),
      socket.assigns.game.scanner_interval
    )
  end

  defp broadcast_after(socket, ref_key, topic, interval) do
    ref =
      Process.send_after(
        self(),
        {:broadcast_tick, topic},
        interval
      )

    assign(socket, ref_key, ref)
  end

  defp cancel_timer(socket, ref_key) do
    case socket.assigns[ref_key] do
      nil ->
        socket

      ref ->
        Process.cancel_timer(ref)
        assign(socket, ref_key, nil)
    end
  end

  defp cancel_timers(socket) do
    socket
    |> cancel_timer(:gravity_ref)
    |> cancel_timer(:scanner_ref)
    |> cancel_timer(:move_timer_ref)
    |> assign(held_keys: MapSet.new(), move_interval: @initial_move_interval)
  end

  defp handle_directional_input(socket, "ArrowLeft") do
    update_game(socket, &Engine.move_left/1)
  end

  defp handle_directional_input(socket, "ArrowRight") do
    update_game(socket, &Engine.move_right/1)
  end

  defp start_move_timer(%{assigns: %{move_timer_ref: ref}} = socket) when not is_nil(ref) do
    socket
  end

  defp start_move_timer(socket) do
    socket
    |> assign(:move_interval, @initial_move_interval)
    |> schedule_move_tick()
  end

  defp schedule_move_tick(socket) do
    socket
    |> cancel_timer(:move_timer_ref)
    |> broadcast_after(
      :move_timer_ref,
      move_topic(socket.assigns.session_id),
      socket.assigns.move_interval
    )
  end

  defp maybe_cancel_move_timer(socket, %MapSet{} = held_keys) do
    case MapSet.size(held_keys) do
      0 -> cancel_move_timer(socket)
      _ -> socket
    end
  end

  defp cancel_move_timer(socket) do
    socket
    |> cancel_timer(:move_timer_ref)
    |> assign(move_interval: @initial_move_interval)
  end

  # --- PubSub Topic Helpers ---

  defp subscribe_to_topics(socket) do
    session_id = socket.assigns.session_id
    Phoenix.PubSub.subscribe(Eclipse.PubSub, gravity_topic(session_id))
    Phoenix.PubSub.subscribe(Eclipse.PubSub, scanner_topic(session_id))
    Phoenix.PubSub.subscribe(Eclipse.PubSub, move_topic(session_id))
    socket
  end

  defp gravity_topic(session_id), do: "game:#{session_id}:gravity"
  defp scanner_topic(session_id), do: "game:#{session_id}:scanner"
  defp move_topic(session_id), do: "game:#{session_id}:move"

  defp generate_session_id do
    16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
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
