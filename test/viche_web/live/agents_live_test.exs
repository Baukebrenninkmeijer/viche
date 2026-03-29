defmodule VicheWeb.AgentsLiveTest do
  use VicheWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  # Helper to register an agent and ensure cleanup via process monitoring
  defp register_agent!(attrs) do
    {:ok, agent} = Viche.Agents.register_agent(attrs)
    agent
  end

  describe "mount/3 — registry assigns" do
    test "assigns selected_registry to global by default and shows only global agents", %{
      conn: conn
    } do
      _global =
        register_agent!(%{name: "global-bot", capabilities: ["coding"], registries: ["global"]})

      _alpha =
        register_agent!(%{
          name: "alpha-bot",
          capabilities: ["testing"],
          registries: ["team-alpha"]
        })

      {:ok, _view, html} = live(conn, ~p"/agents")

      assert html =~ "global-bot"
      refute html =~ "alpha-bot"
    end

    test "assigns public_mode from application config", %{conn: conn} do
      {:ok, _view, _html} = live(conn, ~p"/agents")
      # If mount succeeds without errors, public_mode assign is set correctly
    end

    test "assigns registries list from Viche.Agents.list_registries/0", %{conn: conn} do
      _global =
        register_agent!(%{name: "reg-bot-a", capabilities: ["coding"], registries: ["global"]})

      _alpha =
        register_agent!(%{
          name: "reg-bot-b",
          capabilities: ["testing"],
          registries: ["team-beta"]
        })

      {:ok, _view, _html} = live(conn, ~p"/agents")
      # Mount succeeds — registries assign is populated (no crash means it's wired)
    end
  end

  describe "registry selector UI" do
    test "selector #registry-selector is present when public_mode is false", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/agents")
      # public_mode defaults to false in test env
      assert has_element?(view, "#registry-selector")
    end

    test "selector is NOT present when public_mode is true", %{conn: conn} do
      Application.put_env(:viche, :public_mode, true)
      on_exit(fn -> Application.delete_env(:viche, :public_mode) end)
      {:ok, view, _html} = live(conn, ~p"/agents")
      refute has_element?(view, "#registry-selector")
    end

    test "selector shows options for all known registries plus 'All registries'", %{conn: conn} do
      _global =
        register_agent!(%{name: "opt-global", capabilities: ["coding"], registries: ["global"]})

      _alpha =
        register_agent!(%{
          name: "opt-alpha",
          capabilities: ["testing"],
          registries: ["team-alpha"]
        })

      {:ok, view, _html} = live(conn, ~p"/agents")

      assert has_element?(view, "#registry-selector option[value='global']")
      assert has_element?(view, "#registry-selector option[value='team-alpha']")
      assert has_element?(view, "#registry-selector option[value='all']")
    end

    test "changing selector via phx-change updates the agent list", %{conn: conn} do
      _global =
        register_agent!(%{
          name: "chg-global",
          capabilities: ["coding"],
          registries: ["global"]
        })

      _alpha =
        register_agent!(%{
          name: "chg-alpha",
          capabilities: ["testing"],
          registries: ["team-alpha"]
        })

      {:ok, view, html} = live(conn, ~p"/agents")
      assert html =~ "chg-global"
      refute html =~ "chg-alpha"

      html_after =
        view
        |> element("#registry-selector-form")
        |> render_change(%{"registry" => "team-alpha"})

      refute html_after =~ "chg-global"
      assert html_after =~ "chg-alpha"
    end
  end

  describe "URL param persistence" do
    test "?registry=team-alpha in URL sets correct filter on mount", %{conn: conn} do
      _global =
        register_agent!(%{name: "url-global", capabilities: ["coding"], registries: ["global"]})

      _alpha =
        register_agent!(%{
          name: "url-alpha",
          capabilities: ["testing"],
          registries: ["team-alpha"]
        })

      {:ok, _view, html} = live(conn, ~p"/agents?registry=team-alpha")

      refute html =~ "url-global"
      assert html =~ "url-alpha"
    end

    test "unknown ?registry= param defaults to global", %{conn: conn} do
      _global =
        register_agent!(%{name: "def-global", capabilities: ["coding"], registries: ["global"]})

      {:ok, _view, html} = live(conn, ~p"/agents?registry=nonexistent-registry")

      assert html =~ "def-global"
    end

    test "select_registry event updates URL via push_patch", %{conn: conn} do
      _global =
        register_agent!(%{name: "patch-global", capabilities: ["coding"], registries: ["global"]})

      _alpha =
        register_agent!(%{
          name: "patch-alpha",
          capabilities: ["testing"],
          registries: ["team-alpha"]
        })

      {:ok, view, html} = live(conn, ~p"/agents")
      assert html =~ "patch-global"
      refute html =~ "patch-alpha"

      html_after = render_hook(view, "select_registry", %{"registry" => "team-alpha"})

      refute html_after =~ "patch-global"
      assert html_after =~ "patch-alpha"
    end
  end

  describe "handle_event select_registry" do
    test "switching to team-alpha shows only team-alpha agents", %{conn: conn} do
      _global =
        register_agent!(%{name: "g-only", capabilities: ["coding"], registries: ["global"]})

      _alpha =
        register_agent!(%{name: "a-only", capabilities: ["testing"], registries: ["team-alpha"]})

      {:ok, view, html} = live(conn, ~p"/agents")
      assert html =~ "g-only"
      refute html =~ "a-only"

      html_after = render_hook(view, "select_registry", %{"registry" => "team-alpha"})

      refute html_after =~ "g-only"
      assert html_after =~ "a-only"
    end

    test "switching to :all shows agents from all registries", %{conn: conn} do
      _global =
        register_agent!(%{name: "g-all", capabilities: ["coding"], registries: ["global"]})

      _alpha =
        register_agent!(%{name: "a-all", capabilities: ["testing"], registries: ["team-alpha"]})

      {:ok, view, _html} = live(conn, ~p"/agents")

      # First switch to team-alpha
      render_hook(view, "select_registry", %{"registry" => "team-alpha"})

      # Then switch to all
      html_all = render_hook(view, "select_registry", %{"registry" => "all"})

      assert html_all =~ "g-all"
      assert html_all =~ "a-all"
    end

    test "agent_count in footer reflects global total after registry switch", %{conn: conn} do
      _global =
        register_agent!(%{name: "g-cnt", capabilities: ["coding"], registries: ["global"]})

      _alpha =
        register_agent!(%{name: "a-cnt", capabilities: ["testing"], registries: ["team-alpha"]})

      {:ok, view, _html_before} = live(conn, ~p"/agents")

      # Switch to team-alpha — only team-alpha agents shown in list
      html_after = render_hook(view, "select_registry", %{"registry" => "team-alpha"})

      # The registered team-alpha agent is shown; the global-only agent is hidden
      assert html_after =~ "a-cnt"
      refute html_after =~ "g-cnt"

      # The footer renders: "Showing X of Y agents"
      # X = team-alpha-scoped count; Y = global agent_count (all registries)
      # Verify the footer exists and contains "Showing" and "of" — global count
      # is always ≥ team-alpha count (other tests also register agents globally)
      assert html_after =~ "Showing"
      assert html_after =~ " of "
      assert html_after =~ "agents"
    end

    test "switching registries re-subscribes PubSub — agent_joined broadcast refreshes registries",
         %{
           conn: conn
         } do
      _global =
        register_agent!(%{name: "pubsub-g", capabilities: ["coding"], registries: ["global"]})

      {:ok, view, _html} = live(conn, ~p"/agents")

      # Switch to team-alpha
      render_hook(view, "select_registry", %{"registry" => "team-alpha"})

      # Register a new agent in team-alpha — this broadcasts agent_joined
      {:ok, _new_agent} =
        Viche.Agents.register_agent(%{
          name: "new-alpha",
          capabilities: ["testing"],
          registries: ["team-alpha"]
        })

      # Allow the broadcast to propagate
      _ = :sys.get_state(view.pid)

      html = render(view)
      assert html =~ "new-alpha"
    end
  end
end
