defmodule EclipseWeb.GameLiveTest do
  use EclipseWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders game in waiting state", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/play")
    assert has_element?(view, "#eclipse-game")
    assert has_element?(view, "#start-btn")
  end

  test "starts game on start button click", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/play")
    view |> element("#start-btn") |> render_click()
    refute has_element?(view, "#start-btn")
    assert has_element?(view, "#game-board")
  end

  test "renders game board with cells", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/play")
    view |> element("#start-btn") |> render_click()
    assert has_element?(view, "#cell-0-0")
    assert has_element?(view, "#cell-23-9")
  end

  test "renders queue panel", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/play")
    assert has_element?(view, "#queue-panel")
    assert has_element?(view, "#queue-0")
    assert has_element?(view, "#queue-1")
    assert has_element?(view, "#queue-2")
  end

  test "responds to keyboard input without crash", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/play")
    view |> element("#start-btn") |> render_click()
    render_keydown(view, "keydown", %{"key" => "ArrowLeft"})
    render_keydown(view, "keydown", %{"key" => "ArrowRight"})
    render_keydown(view, "keydown", %{"key" => "ArrowDown"})
    render_keydown(view, "keydown", %{"key" => "ArrowUp"})
    render_keydown(view, "keydown", %{"key" => " "})
    assert has_element?(view, "#game-board")
  end

  test "gravity tick progresses game", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/play")
    view |> element("#start-btn") |> render_click()
    send(view.pid, :gravity_tick)
    render(view)
    assert has_element?(view, "#game-board")
  end
end
