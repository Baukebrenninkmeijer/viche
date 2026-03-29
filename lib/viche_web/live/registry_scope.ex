defmodule VicheWeb.Live.RegistryScope do
  @moduledoc """
  Shared helpers for registry-scoped LiveView state and PubSub management.

  Provides normalized subscription switching so every registry-aware LiveView
  shares the same semantics for:
    - Translating a registry string from UI params to domain-layer arguments
    - Subscribing / unsubscribing from Phoenix PubSub registry topics
    - Switching from one registry to another (no-op when registry is unchanged)
  """

  @doc """
  Converts a UI-facing registry string to the domain-layer argument expected by
  `Viche.Agents.list_agents_with_status/1`.

  The special value `"all"` maps to the `:all` atom; everything else is passed through.
  """
  @spec to_filter(String.t()) :: String.t() | :all
  def to_filter("all"), do: :all
  def to_filter(registry), do: registry

  @doc """
  Switches PubSub subscriptions from `old_registry` to `new_registry`.

  No-op when both values are identical.
  """
  @spec switch(String.t(), String.t()) :: :ok
  def switch(same, same), do: :ok

  def switch(old, new) do
    unsubscribe(old)
    subscribe(new)
  end

  @doc """
  Subscribes to PubSub topic(s) for the given registry.

  When `registry` is `"all"`, subscribes to every currently known registry topic.
  """
  @spec subscribe(String.t()) :: :ok
  def subscribe("all") do
    Enum.each(Viche.Agents.list_registries(), fn r ->
      Phoenix.PubSub.subscribe(Viche.PubSub, "registry:#{r}")
    end)
  end

  def subscribe(registry) when is_binary(registry) do
    Phoenix.PubSub.subscribe(Viche.PubSub, "registry:#{registry}")
    :ok
  end

  @doc """
  Unsubscribes from PubSub topic(s) for the given registry.

  When `registry` is `"all"`, unsubscribes from every currently known registry topic.
  """
  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe("all") do
    Enum.each(Viche.Agents.list_registries(), fn r ->
      Phoenix.PubSub.unsubscribe(Viche.PubSub, "registry:#{r}")
    end)
  end

  def unsubscribe(registry) when is_binary(registry) do
    Phoenix.PubSub.unsubscribe(Viche.PubSub, "registry:#{registry}")
    :ok
  end
end
