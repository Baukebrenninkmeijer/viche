defmodule VicheWeb.RegistryController do
  @moduledoc """
  Handles agent registration and discovery in the Viche registry.
  """

  use VicheWeb, :controller

  alias Viche.AgentServer

  @spec register(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def register(conn, params) do
    capabilities = Map.get(params, "capabilities")

    if valid_capabilities?(capabilities) do
      agent_id = generate_unique_id()
      name = Map.get(params, "name")
      description = Map.get(params, "description")

      child_spec =
        {AgentServer,
         [
           id: agent_id,
           name: name,
           capabilities: capabilities,
           description: description
         ]}

      {:ok, _pid} = DynamicSupervisor.start_child(Viche.AgentSupervisor, child_spec)

      via = {:via, Registry, {Viche.AgentRegistry, agent_id}}
      agent = AgentServer.get_state(via)

      conn
      |> put_status(:created)
      |> json(%{
        id: agent.id,
        name: agent.name,
        capabilities: agent.capabilities,
        description: agent.description,
        inbox_url: "/inbox/#{agent.id}",
        registered_at: DateTime.to_iso8601(agent.registered_at)
      })
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "capabilities_required"})
    end
  end

  @spec discover(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def discover(conn, %{"capability" => cap}) when cap != "" do
    json(conn, %{agents: find_by_capability(cap)})
  end

  def discover(conn, %{"name" => name}) when name != "" do
    json(conn, %{agents: find_by_name(name)})
  end

  def discover(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "query_required",
      message: "Provide ?capability= or ?name= parameter"
    })
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec valid_capabilities?(term()) :: boolean()
  defp valid_capabilities?(capabilities) when is_list(capabilities) and capabilities != [],
    do: true

  defp valid_capabilities?(_), do: false

  @spec generate_unique_id() :: String.t()
  defp generate_unique_id do
    id = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    case Registry.lookup(Viche.AgentRegistry, id) do
      [] -> id
      _ -> generate_unique_id()
    end
  end

  @spec all_agents() :: [{String.t(), map()}]
  defp all_agents do
    Registry.select(Viche.AgentRegistry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$3"}}]}])
  end

  @spec find_by_capability(String.t()) :: [map()]
  defp find_by_capability(capability) do
    for {id, meta} <- all_agents(),
        capability in meta.capabilities do
      format_agent({id, meta})
    end
  end

  @spec find_by_name(String.t()) :: [map()]
  defp find_by_name(name) do
    for {id, meta} <- all_agents(),
        meta.name == name do
      format_agent({id, meta})
    end
  end

  @spec format_agent({String.t(), map()}) :: map()
  defp format_agent({id, meta}) do
    %{
      id: id,
      name: meta.name,
      capabilities: meta.capabilities,
      description: meta.description
    }
  end
end
