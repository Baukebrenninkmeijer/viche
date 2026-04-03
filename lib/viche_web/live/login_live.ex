defmodule VicheWeb.LoginLive do
  use VicheWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Viche.PubSub, "metrics:messages")
      :timer.send_interval(10_000, :refresh_agents)
    end

    agents_online =
      Viche.Agents.list_agents_with_status()
      |> Enum.count(fn agent -> agent.status == :online end)

    {:ok,
     assign(socket,
       form: to_form(%{"email" => ""}, as: :login),
       state: :form,
       agents_online: agents_online,
       messages_today: Viche.MessageCounter.get()
     ), layout: false}
  end

  @impl true
  def handle_event("send_magic_link", %{"login" => %{"email" => email}}, socket) do
    email = String.trim(email)

    if valid_email?(email) do
      Viche.Auth.send_magic_link(email)
      {:noreply, assign(socket, state: :success)}
    else
      {:noreply,
       socket
       |> assign(form: to_form(%{"email" => email}, as: :login))
       |> put_flash(:error, "Please enter a valid email address")}
    end
  end

  @impl true
  def handle_info({:messages_today, count}, socket) do
    {:noreply, assign(socket, messages_today: count)}
  end

  @impl true
  def handle_info(:refresh_agents, socket) do
    agents_online =
      Viche.Agents.list_agents_with_status()
      |> Enum.count(fn agent -> agent.status == :online end)

    {:noreply, assign(socket, agents_online: agents_online)}
  end

  defp valid_email?(email) do
    String.match?(email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/)
  end
end
