defmodule VicheWeb.RegistryControllerPrivacyArgusTest do
  use VicheWeb.ConnCase, async: false

  describe "GET /registry/discover" do
    setup do
      Viche.AgentSupervisor
      |> DynamicSupervisor.which_children()
      |> Enum.each(fn {_, pid, _, _} ->
        DynamicSupervisor.terminate_child(Viche.AgentSupervisor, pid)
      end)

      :ok
    end

    test "does not expose private registry tokens in discovery responses", %{conn: conn} do
      private_token = "secret-registry"

      {:ok, _agent} =
        Viche.Agents.register_agent(%{
          capabilities: ["coding"],
          name: "private-agent",
          registries: ["global", private_token]
        })

      conn = get(conn, ~p"/registry/discover", %{capability: "coding"})

      assert %{"agents" => [agent]} = json_response(conn, 200)

      refute private_token in (agent["registries"] || [])
    end
  end
end
