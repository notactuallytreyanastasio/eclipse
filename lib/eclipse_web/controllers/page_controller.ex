defmodule EclipseWeb.PageController do
  use EclipseWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
