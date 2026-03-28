defmodule VicheWeb.DemoLive do
  use VicheWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    agents = Viche.Agents.list_agents()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Viche.PubSub, "demo:joins")
      Phoenix.PubSub.subscribe(Viche.PubSub, "registry:global")
      Process.send_after(self(), :fake_join, :rand.uniform(5000) + 5000)
    end

    {:ok,
     assign(socket,
       join_count: 0,
       qr_hash: "a8f3c2",
       agent_count: length(agents),
       messages_today: 0
     )}
  end

  @impl true
  def handle_info(:fake_join, socket) do
    count = socket.assigns.join_count

    if count < 50 do
      Process.send_after(self(), :fake_join, :rand.uniform(5000) + 4000)
      {:noreply, assign(socket, join_count: count + 1)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "new_join"}, socket) do
    {:noreply, assign(socket, join_count: socket.assigns.join_count + 1)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "agent_joined"}, socket) do
    {:noreply, assign(socket, agent_count: length(Viche.Agents.list_agents()))}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "agent_left"}, socket) do
    {:noreply, assign(socket, agent_count: length(Viche.Agents.list_agents()))}
  end

  def handle_info(_, socket), do: {:noreply, socket}
end
