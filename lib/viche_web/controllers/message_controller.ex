defmodule VicheWeb.MessageController do
  @moduledoc """
  Handles sending messages to agent inboxes.

  Thin HTTP adapter — all business logic lives in `Viche.Agents`.
  """

  use VicheWeb, :controller

  alias Viche.Agents

  @spec send_message(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def send_message(conn, %{"agent_id" => agent_id, "type" => type, "from" => from, "body" => body}) do
    attrs = %{to: agent_id, from: from, body: body, type: type}

    case Agents.send_message(attrs) do
      {:ok, message_id} ->
        conn
        |> put_status(:accepted)
        |> json(%{message_id: message_id})

      {:error, :agent_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "agent_not_found"})

      {:error, :invalid_message} ->
        invalid_message_response(conn)
    end
  end

  def send_message(conn, _params), do: invalid_message_response(conn)

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec invalid_message_response(Plug.Conn.t()) :: Plug.Conn.t()
  defp invalid_message_response(conn) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "invalid_message", message: "type, from, and body are required"})
  end
end
