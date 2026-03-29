defmodule VicheWeb.DashboardLive do
  use VicheWeb, :live_view

  alias VicheWeb.Live.RegistryScope

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:selected_registry, "global")
      |> assign(:public_mode, Application.get_env(:viche, :public_mode, false))
      |> assign(:registries, Viche.Agents.list_registries())
      |> load_and_assign_agents()

    if connected?(socket) do
      RegistryScope.subscribe("global")
      Phoenix.PubSub.subscribe(Viche.PubSub, "dashboard:feed")
      subscribe_to_all_agents(socket.assigns.agents)
      Process.send_after(self(), :tick, 10_000)
    end

    socket =
      socket
      |> assign(:feed, [])
      |> assign(:messages_today, 0)
      |> assign(:queued_messages, total_queued_messages(socket.assigns.agents))
      |> assign(:paused, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    registry = Map.get(params, "registry", "global")
    registry = validate_registry(registry, socket.assigns.registries)
    old_registry = socket.assigns.selected_registry

    if connected?(socket) do
      RegistryScope.switch(old_registry, registry)
    end

    socket =
      socket
      |> assign(:selected_registry, registry)
      |> load_and_assign_agents()

    {:noreply, socket}
  end

  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, 10_000)

    socket =
      socket
      |> load_and_assign_agents()
      |> assign(:queued_messages, total_queued_messages(socket.assigns.agents))

    {:noreply, socket}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "registry:" <> _,
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

    Phoenix.PubSub.subscribe(Viche.PubSub, "agent:#{payload.id}")

    socket =
      socket
      |> assign(:registries, Viche.Agents.list_registries())
      |> load_and_assign_agents()
      |> update(:feed, fn feed -> [event | Enum.take(feed, 49)] end)

    {:noreply, socket}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "registry:" <> _,
          event: "agent_left",
          payload: payload
        },
        socket
      ) do
    event = %{
      type: "leave",
      from: payload.id,
      to: "registry",
      body: "Agent disconnected",
      at: "just now"
    }

    socket =
      socket
      |> assign(:registries, Viche.Agents.list_registries())
      |> load_and_assign_agents()
      |> update(:feed, fn feed -> [event | Enum.take(feed, 49)] end)

    {:noreply, socket}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "agent:" <> _agent_id,
          event: "new_message",
          payload: message
        },
        socket
      ) do
    event = %{
      type: message.type,
      from: message.from,
      to: message[:to] || "unknown",
      body: message.body,
      at: "just now"
    }

    socket =
      socket
      |> update(:messages_today, &(&1 + 1))
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

  def handle_event("select_registry", %{"registry" => registry}, socket) do
    {:noreply, push_patch(socket, to: ~p"/dashboard?registry=#{registry}")}
  end

  # -- Helpers --

  defp validate_registry(registry, registries) do
    if registry in (["global", "all"] ++ registries), do: registry, else: "global"
  end

  defp load_and_assign_agents(socket) do
    filter = RegistryScope.to_filter(socket.assigns.selected_registry)
    agents = Viche.Agents.list_agents_with_status(filter)
    all_global = Viche.Agents.list_agents_with_status(:all)
    online = Enum.count(all_global, &(&1.status == :online))

    socket
    |> assign(:agents, agents)
    |> assign(:agent_count, length(all_global))
    |> assign(:online_count, online)
  end

  defp subscribe_to_all_agents(agents) do
    Enum.each(agents, fn agent ->
      Phoenix.PubSub.subscribe(Viche.PubSub, "agent:#{agent.id}")
    end)
  end

  defp total_queued_messages(agents) do
    Enum.sum(Enum.map(agents, & &1.queue_depth))
  end
end
