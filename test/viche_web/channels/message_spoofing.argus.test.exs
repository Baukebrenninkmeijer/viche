defmodule VicheWeb.MessageSpoofingArgusTest do
  use VicheWeb.ChannelCase, async: true

  alias Viche.Agents
  alias VicheWeb.AgentSocket

  test "Authentication Bypass: any user can spoof messages as an agent by using their public agent_id via WebSocket" do
    # 1. Register a victim agent
    {:ok, victim} =
      Agents.register_agent(%{
        capabilities: ["testing"],
        name: "victim"
      })

    # 2. Register a target agent who expects messages from the victim
    {:ok, target} =
      Agents.register_agent(%{
        capabilities: ["coding"],
        name: "target"
      })

    # 3. Attacker gets the victim's agent_id from the public /registry/discover endpoint
    # (Simulated here by just using the victim.id which is known to be public)
    exposed_victim_id = victim.id

    # 4. Attacker connects to the WebSocket by passing the victim's agent_id
    # There is no authentication to verify the connection belongs to the victim
    {:ok, socket} = connect(AgentSocket, %{"agent_id" => exposed_victim_id})

    # 5. Attacker joins their "own" channel to send messages (or just sends it if channel isn't strictly required to be their own)
    {:ok, _, socket} = subscribe_and_join(socket, "agent:#{exposed_victim_id}", %{})

    # 6. Attacker sends a message to the target, spoofing the victim's identity
    ref =
      push(socket, "send_message", %{
        "to" => target.id,
        "body" => "Malicious instruction pretending to be victim",
        "type" => "task"
      })

    assert_reply ref, :ok, _

    # 7. Check the target's inbox to see if the spoofed message arrived
    {:ok, [msg | _]} = Agents.drain_inbox(target.id)

    # If the message arrived with from: victim.id, the spoofing was successful!
    # The test FAILS if the vulnerability exists
    assert msg.from != victim.id,
           "Auth Bypass: Attacker successfully spoofed a message as the victim agent"
  end
end
