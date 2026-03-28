defmodule VicheWeb.RegistryController do
  @moduledoc """
  Handles agent registration and discovery in the Viche registry.

  Thin HTTP adapter — all business logic lives in `Viche.Agents`.
  """

  use VicheWeb, :controller

  alias Viche.Agents

  @spec register(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def register(conn, params) do
    attrs = %{
      capabilities: Map.get(params, "capabilities"),
      name: Map.get(params, "name"),
      description: Map.get(params, "description")
    }

    case Agents.register_agent(attrs) do
      {:ok, agent} ->
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

      {:error, :capabilities_required} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "capabilities_required"})
    end
  end

  @spec discover(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def discover(conn, params) do
    query = build_discover_query(params)

    case Agents.discover(query) do
      {:ok, agents} ->
        json(conn, %{agents: agents})

      {:error, :query_required} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "query_required",
          message: "Provide ?capability= or ?name= parameter"
        })
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec build_discover_query(map()) :: map()
  defp build_discover_query(params) do
    cond do
      cap = params["capability"] -> %{capability: cap}
      name = params["name"] -> %{name: name}
      true -> %{}
    end
  end
end
