defmodule VicheWeb.SignupLiveTest do
  use VicheWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "GET /signup" do
    test "renders the signup form", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/signup")

      assert html =~ "Create your account"
      assert html =~ "Join the agent network"
      assert html =~ "ada@example.com"
    end

    test "does not render password field", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/signup")

      refute html =~ "password"
      refute html =~ "Password"
    end
  end

  describe "multi-step navigation" do
    test "advances to step 2 after valid name and email", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/signup")

      html =
        view
        |> form("form", %{"user" => %{"name" => "Ada Lovelace", "email" => "ada@example.com"}})
        |> render_submit()

      assert html =~ "Username"
      assert html =~ "@"
    end

    test "shows error when name is empty on step 1", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/signup")

      html =
        view
        |> form("form", %{"user" => %{"name" => "", "email" => "ada@example.com"}})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    test "shows error when email is invalid on step 1", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/signup")

      html =
        view
        |> form("form", %{"user" => %{"name" => "Ada", "email" => "not-an-email"}})
        |> render_submit()

      assert html =~ "must have the @ sign and no spaces"
    end

    test "goes back from step 2 to step 1", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/signup")

      view
      |> form("form", %{"user" => %{"name" => "Ada", "email" => "ada@example.com"}})
      |> render_submit()

      html = view |> element("button", "Back") |> render_click()

      assert html =~ "Name"
      assert html =~ "Email"
    end

    test "advances to step 3 after valid username", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/signup")

      view
      |> form("form", %{"user" => %{"name" => "Ada", "email" => "ada@example.com"}})
      |> render_submit()

      html =
        view
        |> form("form", %{"user" => %{"username" => "ada_lovelace"}})
        |> render_submit()

      assert html =~ "How do you plan to use Viche?"
    end

    test "shows error for invalid username", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/signup")

      view
      |> form("form", %{"user" => %{"name" => "Ada", "email" => "ada@example.com"}})
      |> render_submit()

      html =
        view
        |> form("form", %{"user" => %{"username" => ""}})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end
  end

  describe "submit" do
    test "shows success state after completing all steps", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/signup")

      # Step 1
      view
      |> form("form", %{"user" => %{"name" => "Ada Lovelace", "email" => "signup@example.com"}})
      |> render_submit()

      # Step 2
      view
      |> form("form", %{"user" => %{"username" => "ada_signup"}})
      |> render_submit()

      # Step 3
      view |> element("[phx-value-value=personal]") |> render_click()

      html =
        view
        |> form("form")
        |> render_submit()

      assert html =~ "Check your email"
      assert html =~ "magic link"
      refute html =~ "Create your account"
    end

    test "shows error when no use case selected", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/signup")

      # Step 1
      view
      |> form("form", %{"user" => %{"name" => "Ada", "email" => "ada@example.com"}})
      |> render_submit()

      # Step 2
      view
      |> form("form", %{"user" => %{"username" => "ada_test"}})
      |> render_submit()

      # Step 3 - no use case selected
      html =
        view
        |> form("form")
        |> render_submit()

      assert html =~ "Please select how you plan to use Viche"
    end
  end
end
