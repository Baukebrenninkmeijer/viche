defmodule VicheWeb.MessageController do
  @moduledoc """
  Handles sending messages to agent inboxes.
  """

  use VicheWeb, :controller

  alias Viche.AgentServer
  alias Viche.Message

  @spec send_message(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def send_message(conn, %{"agent_id" => agent_id} = params) do
    type = Map.get(params, "type")
    from = Map.get(params, "from")
    body = Map.get(params, "body")

    if valid_params?(type, from, body) do
      via = {:via, Registry, {Viche.AgentRegistry, agent_id}}

      case lookup_agent(agent_id) do
        :not_found ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "agent_not_found"})

        :found ->
          message = %Message{
            id: generate_message_id(),
            type: type,
            from: from,
            body: body,
            sent_at: DateTime.utc_now()
          }

          AgentServer.receive_message(via, message)

          conn
          |> put_status(:accepted)
          |> json(%{message_id: message.id})
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "invalid_message", message: "type, from, and body are required"})
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec valid_params?(term(), term(), term()) :: boolean()
  defp valid_params?(type, from, body)
       when is_binary(type) and is_binary(from) and is_binary(body) and from != "" and body != "" do
    Message.valid_type?(type)
  end

  defp valid_params?(_, _, _), do: false

  @spec lookup_agent(String.t()) :: :found | :not_found
  defp lookup_agent(agent_id) do
    case Registry.lookup(Viche.AgentRegistry, agent_id) do
      [] -> :not_found
      _ -> :found
    end
  end

  @spec generate_message_id() :: String.t()
  defp generate_message_id do
    hex = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "msg-#{hex}"
  end
end
