defmodule Hello162Web.PageController do
  use Hello162Web, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
