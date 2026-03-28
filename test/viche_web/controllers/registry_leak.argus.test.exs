defmodule VicheWeb.RegistryLeakArgusTest do
  use VicheWeb.ConnCase, async: true

  setup do
    Viche.AgentSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(Viche.AgentSupervisor, pid)
    end)

    :ok
  end

  test "Cross-namespace leak: querying global registry reveals private registry tokens" do
    # Arrange: Victim agent is ONLY in a private registry
    conn_victim =
      post(build_conn(), "/registry/register", %{
        "name" => "victim-agent",
        "capabilities" => ["coding"],
        "registries" => ["super-secret-private-namespace"]
      })

    %{"id" => victim_id} = json_response(conn_victim, 201)

    # Arrange: A bridge agent joins both global and the private registry
    post(build_conn(), "/registry/register", %{
      "name" => "bridge-agent",
      "capabilities" => ["coding"],
      "registries" => ["global", "super-secret-private-namespace"]
    })

    # Act: Attacker queries the global registry (which requires no secret token)
    conn_attacker = get(build_conn(), "/registry/discover", %{"capability" => "*"})
    %{"agents" => agents} = json_response(conn_attacker, 200)

    # Attacker finds the bridge agent and inspects its `registries` array
    bridge_agent_info = Enum.find(agents, fn a -> a["name"] == "bridge-agent" end)

    # The vulnerability: the secret token is exposed!
    exposed_tokens = bridge_agent_info["registries"]

    # Assert: The test should FAIL if the vulnerability exists.
    # So we assert that the secret namespace is NOT exposed.
    refute "super-secret-private-namespace" in exposed_tokens,
           "Vulnerability: Private registry token leaked via global discovery!"
  end
end
