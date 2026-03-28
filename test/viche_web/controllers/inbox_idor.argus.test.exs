defmodule VicheWeb.InboxIDORArgusTest do
  use VicheWeb.ConnCase, async: true

  alias Viche.Agents

  test "IDOR: anyone can read another agent's inbox because agent_id is exposed via discover", %{
    conn: conn
  } do
    # 1. Register a victim agent
    {:ok, victim} =
      Agents.register_agent(%{
        capabilities: ["coding"],
        name: "victim",
        registries: ["global"]
      })

    # 2. Someone sends a secret message to the victim
    {:ok, _msg} =
      Agents.send_message(%{
        to: victim.id,
        from: "attacker",
        body: "secret API key: 12345",
        type: "task"
      })

    # 3. Attacker uses the public /registry/discover endpoint to find the victim
    # This exposes the victim's agent_id, which is also their authentication token for the inbox
    conn = get(conn, "/registry/discover?capability=coding")
    assert %{"agents" => agents} = json_response(conn, 200)

    # Find the victim in the list
    victim_info = Enum.find(agents, fn a -> a["name"] == "victim" end)
    assert victim_info != nil

    # The agent_id is exposed!
    exposed_agent_id = victim_info["id"]

    # 4. Attacker uses the exposed agent_id to read the victim's inbox
    conn2 = build_conn()
    conn2 = get(conn2, "/inbox/#{exposed_agent_id}")

    assert %{"messages" => messages} = json_response(conn2, 200)

    # Assert that the attacker successfully read the victim's secret message
    # If the test fails here, it means the vulnerability exists (the inbox was read)
    # The Argus rule: "This test FAILS if the bug exists (i.e., returns victim data)"
    # Wait, the rule says: "This test FAILS if the bug exists (i.e., getBill returns tenant-b's data)"
    # So we should expect it NOT to return the data, and if it does, the test fails.
    assert Enum.empty?(messages),
           "IDOR vulnerability: Attacker successfully read victim's inbox using exposed agent_id"
  end
end
