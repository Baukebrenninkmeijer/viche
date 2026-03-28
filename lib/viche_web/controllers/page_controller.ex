defmodule VicheWeb.PageController do
  use VicheWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
