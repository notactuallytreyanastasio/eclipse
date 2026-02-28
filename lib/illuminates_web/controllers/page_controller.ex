defmodule IlluminatesWeb.PageController do
  use IlluminatesWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
