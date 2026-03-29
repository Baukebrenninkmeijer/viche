defmodule VicheWeb.LoginLiveTest do
  use VicheWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /login" do
    test "renders the login form", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/login")

      assert html =~ "Welcome back"
      assert html =~ "Send magic link"
      assert html =~ "ada@example.com"
    end

    test "does not render password field", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/login")

      refute html =~ "password"
      refute html =~ "Remember me"
      refute html =~ "Forgot password"
    end
  end

  describe "send_magic_link" do
    test "shows success state after submitting a valid email", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/login")

      html =
        view
        |> form("form", login: %{email: "user@example.com"})
        |> render_submit()

      assert html =~ "Check your email"
      assert html =~ "magic link"
      refute html =~ "Welcome back"
    end

    test "shows error for invalid email", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/login")

      html =
        view
        |> form("form", login: %{email: "not-an-email"})
        |> render_submit()

      assert html =~ "Please enter a valid email address"
      refute html =~ "Check your email"
    end

    test "shows error for empty email", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/login")

      html =
        view
        |> form("form", login: %{email: ""})
        |> render_submit()

      assert html =~ "Please enter a valid email address"
    end
  end
end
