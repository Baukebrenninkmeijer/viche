defmodule VicheWeb.DashboardLive do
  use VicheWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Viche.PubSub, "registry:global")
      Phoenix.PubSub.subscribe(Viche.PubSub, "dashboard:feed")
      Process.send_after(self(), :tick, 10_000)
    end

    socket =
      socket
      |> load_and_assign_agents()
      |> assign(:feed, seed_feed())
      |> assign(:session_count, 3)
      |> assign(:messages_today, 1247)
      |> assign(:paused, false)

    {:ok, socket}
  end

  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, 10_000)
    {:noreply, load_and_assign_agents(socket)}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "registry:global",
          event: "agent_joined",
          payload: payload
        },
        socket
      ) do
    event = %{
      type: "join",
      from: payload.name,
      to: "registry",
      body: "New agent registered. Capabilities: #{Enum.join(payload.capabilities, ", ")}",
      at: "just now"
    }

    socket =
      socket
      |> load_and_assign_agents()
      |> update(:feed, fn feed -> [event | Enum.take(feed, 49)] end)

    {:noreply, socket}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "registry:global",
          event: "agent_left",
          payload: payload
        },
        socket
      ) do
    event = %{
      type: "join",
      from: payload.id,
      to: "registry",
      body: "Agent disconnected",
      at: "just now"
    }

    socket =
      socket
      |> load_and_assign_agents()
      |> update(:feed, fn feed -> [event | Enum.take(feed, 49)] end)

    {:noreply, socket}
  end

  def handle_info({:feed_event, event}, socket) do
    if socket.assigns.paused do
      {:noreply, socket}
    else
      {:noreply, update(socket, :feed, fn feed -> [event | Enum.take(feed, 49)] end)}
    end
  end

  @impl true
  def handle_event("toggle_pause", _params, socket) do
    {:noreply, assign(socket, :paused, !socket.assigns.paused)}
  end

  def handle_event("navigate", %{"to" => path}, socket) do
    {:noreply, push_navigate(socket, to: path)}
  end

  # -- Helpers --

  defp load_and_assign_agents(socket) do
    agents = Viche.Agents.list_agents() |> Enum.map(&augment_agent/1)
    online = Enum.count(agents, &(&1.status in [:idle, :busy]))

    socket
    |> assign(:agents, agents)
    |> assign(:agent_count, length(agents))
    |> assign(:online_count, online)
  end

  defp augment_agent(agent) do
    statuses = [:idle, :idle, :idle, :busy, :offline]
    status = Enum.at(statuses, :erlang.phash2(agent.name, 5))
    queue = if status == :busy, do: :erlang.phash2(agent.id, 6), else: 0

    Map.merge(agent, %{
      status: status,
      queue_depth: queue,
      last_seen: last_seen_mock(status)
    })
  end

  defp last_seen_mock(:idle), do: "just now"
  defp last_seen_mock(:busy), do: "#{:rand.uniform(30)}s ago"
  defp last_seen_mock(:offline), do: "#{:rand.uniform(60)}m ago"

  defp seed_feed do
    [
      %{
        type: "task",
        from: "geth-hivemind",
        to: "claude-code-1",
        body: "Review PR #47: refactor agent discovery module",
        at: "just now"
      },
      %{
        type: "ack",
        from: "claude-code-1",
        to: "geth-hivemind",
        body: "Task received. Starting review now.",
        at: "4s ago"
      },
      %{
        type: "join",
        from: "demo-agent-joel",
        to: "registry",
        body: "New agent registered. Capabilities: general",
        at: "2m ago"
      }
    ]
  end
end
