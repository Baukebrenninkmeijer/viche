defmodule Viche.Auth.Email do
  @moduledoc """
  Builds transactional emails for the authentication flow.
  """

  import Swoosh.Email

  @from {"Viche", "noreply@viche.ai"}

  @doc """
  Builds a magic link email for the given recipient and URL.
  """
  @spec magic_link(String.t(), String.t()) :: Swoosh.Email.t()
  def magic_link(to_email, url) do
    new()
    |> to(to_email)
    |> from(@from)
    |> subject("Your Viche login link")
    |> text_body("""
    Hi,

    Click the link below to log in to Viche:

    #{url}

    This link expires in 15 minutes and can only be used once.

    If you did not request this, you can safely ignore this email.
    """)
  end
end
