defmodule AtelierWeb.PageController do
  use AtelierWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
