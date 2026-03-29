defmodule VicheWeb.AgentsLive do
  use VicheWeb, :live_view

  alias VicheWeb.Live.RegistryScope

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      RegistryScope.subscribe("global")
      Phoenix.PubSub.subscribe(Viche.PubSub, "metrics:messages")
    end

    socket =
      socket
      |> assign(:filter, :all)
      |> assign(:query, "")
      |> assign(:session_count, 3)
      |> assign(:selected_registry, "global")
      |> assign(:public_mode, Application.get_env(:viche, :public_mode, false))
      |> assign(:registries, Viche.Agents.list_registries())
      |> assign(:messages_today, Viche.MessageCounter.get())
      |> load_agents()

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
      |> load_agents()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", %{"status" => s}, socket) do
    filter = String.to_atom(s)

    socket =
      socket
      |> assign(:filter, filter)
      |> assign(:agents, apply_filters(socket.assigns.all_agents, filter, socket.assigns.query))

    {:noreply, socket}
  end

  def handle_event("search", %{"value" => q}, socket) do
    socket =
      socket
      |> assign(:query, q)
      |> assign(:agents, apply_filters(socket.assigns.all_agents, socket.assigns.filter, q))

    {:noreply, socket}
  end

  def handle_event("select_agent", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: "/agents/#{id}")}
  end

  def handle_event("select_registry", %{"registry" => registry}, socket) do
    {:noreply, push_patch(socket, to: ~p"/agents?registry=#{registry}")}
  end

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{topic: "registry:" <> _, event: event},
        socket
      )
      when event in ["agent_joined", "agent_left"] do
    socket =
      socket
      |> assign(:registries, Viche.Agents.list_registries())
      |> load_agents()

    {:noreply, socket}
  end

  def handle_info({:messages_today, n}, socket),
    do: {:noreply, assign(socket, :messages_today, n)}

  # -- Helpers --

  defp load_agents(socket) do
    filter = RegistryScope.to_filter(socket.assigns.selected_registry)
    display = Viche.Agents.list_agents_with_status(filter)
    all_global = Viche.Agents.list_agents_with_status(:all)
    filtered = apply_filters(display, socket.assigns.filter, socket.assigns.query)
    online = Enum.count(all_global, &(&1.status == :online))

    socket
    |> assign(:all_agents, display)
    |> assign(:agents, filtered)
    |> assign(:agent_count, length(all_global))
    |> assign(:online_count, online)
  end

  defp validate_registry(registry, registries) do
    if registry in (["global", "all"] ++ registries), do: registry, else: "global"
  end

  defp apply_filters(agents, filter, query) do
    agents |> filter_by_status(filter) |> filter_by_query(query)
  end

  defp filter_by_status(agents, :all), do: agents
  defp filter_by_status(agents, :online), do: Enum.filter(agents, &(&1.status == :online))
  defp filter_by_status(agents, :offline), do: Enum.filter(agents, &(&1.status == :offline))
  defp filter_by_status(agents, _), do: agents

  defp filter_by_query(agents, ""), do: agents

  defp filter_by_query(agents, q) do
    q = String.downcase(q)

    Enum.filter(agents, fn a ->
      String.contains?(String.downcase(a.name || ""), q) ||
        Enum.any?(a.capabilities, &String.contains?(String.downcase(&1), q))
    end)
  end
end
