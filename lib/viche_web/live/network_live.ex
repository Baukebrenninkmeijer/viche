defmodule VicheWeb.NetworkLive do
  use VicheWeb, :live_view

  alias VicheWeb.Live.RegistryScope

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      RegistryScope.subscribe("global")
      Phoenix.PubSub.subscribe(Viche.PubSub, "metrics:messages")
      subscribe_to_all_agents(Viche.Agents.list_agents_with_status())
      Process.send_after(self(), :tick, 3_000)
    end

    socket =
      socket
      |> assign(:selected_registry, "global")
      |> assign(:public_mode, Application.get_env(:viche, :public_mode, false))
      |> assign(:registries, Viche.Agents.list_registries())
      |> assign(:feed, [])
      |> assign(:paused, false)
      |> assign(:session_count, 3)
      |> assign(:messages_today, Viche.MessageCounter.get())
      |> load_graph()

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
      |> load_graph_and_push()

    {:noreply, socket}
  end

  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, 3_000)

    {:noreply, load_graph_and_push(socket)}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "registry:" <> _,
          event: "agent_joined",
          payload: payload
        },
        socket
      ) do
    event = %{type: "join", from: payload.name, to: "registry", color: "#A7C080", at: "just now"}

    socket =
      socket
      |> assign(:registries, Viche.Agents.list_registries())
      |> load_graph_and_push()
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
    event = %{type: "task", from: payload.id, to: "registry", color: "#E67E80", at: "just now"}

    socket =
      socket
      |> assign(:registries, Viche.Agents.list_registries())
      |> load_graph_and_push()
      |> update(:feed, fn feed -> [event | Enum.take(feed, 49)] end)

    {:noreply, socket}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "agent:" <> agent_id,
          event: "new_message",
          payload: message
        },
        socket
      ) do
    color =
      case Enum.find(socket.assigns.agents, &(&1.id == agent_id)) do
        nil -> "#A7C080"
        agent -> agent.color
      end

    from_id =
      case Enum.find(socket.assigns.agents, &(&1.name == message.from || &1.id == message.from)) do
        nil -> nil
        agent -> agent.id
      end

    socket =
      socket
      |> update(:messages_today, &(&1 + 1))
      |> update(:feed, fn feed ->
        [
          %{type: message.type, from: message.from, to: agent_id, color: color, at: "just now"}
          | Enum.take(feed, 49)
        ]
      end)

    socket =
      if from_id do
        push_event(socket, "graph_pulse", %{from: from_id, to: agent_id, color: color})
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:messages_today, n}, socket),
    do: {:noreply, assign(socket, :messages_today, n)}

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("toggle_pause", _params, socket) do
    {:noreply, assign(socket, :paused, !socket.assigns.paused)}
  end

  def handle_event("noop", _params, socket), do: {:noreply, socket}

  def handle_event("select_registry", %{"registry" => registry}, socket) do
    {:noreply, push_patch(socket, to: ~p"/network?registry=#{registry}")}
  end

  # -- Helpers --

  defp validate_registry(registry, registries) do
    if registry in (["global", "all"] ++ registries), do: registry, else: "global"
  end

  # Reloads agent graph data from the selected registry and updates assigns.
  defp load_graph(socket) do
    filter = RegistryScope.to_filter(socket.assigns.selected_registry)
    agents = Viche.Agents.list_agents_with_status(filter) |> Enum.map(&add_color/1)
    all_global = Viche.Agents.list_agents_with_status(:all)
    links = compute_links(agents)
    online = Enum.count(all_global, &(&1.status == :online))

    socket
    |> assign(:agents, agents)
    |> assign(:links, links)
    |> assign(:agent_count, length(all_global))
    |> assign(:online_count, online)
  end

  # Reloads graph data and pushes a graph_update event to the client JS hook.
  defp load_graph_and_push(socket) do
    socket = load_graph(socket)

    push_event(socket, "graph_update", %{
      agents:
        Jason.encode!(
          Enum.map(socket.assigns.agents, fn a ->
            %{id: a.id, name: a.name, color: a.color, status: to_string(a.status)}
          end)
        ),
      links: Jason.encode!(socket.assigns.links)
    })
  end

  defp compute_links(agents) do
    ids = Enum.map(agents, & &1.id)
    n = length(ids)

    for i <- 0..(n - 1), j <- (i + 1)..(n - 1), i != j, i + j < n + 3 do
      %{source: Enum.at(ids, i), target: Enum.at(ids, j)}
    end
    |> Enum.take(8)
  end

  defp add_color(agent) do
    Map.put(agent, :color, agent_color(agent.name))
  end

  defp agent_color(name) do
    colors = ["#A7C080", "#7FBBB3", "#D699B6", "#DBBC7F", "#83C092", "#E69875", "#E67E80"]
    Enum.at(colors, rem(:erlang.phash2(name), 7))
  end

  defp subscribe_to_all_agents(agents) do
    Enum.each(agents, fn agent ->
      Phoenix.PubSub.subscribe(Viche.PubSub, "agent:#{agent.id}")
    end)
  end
end
