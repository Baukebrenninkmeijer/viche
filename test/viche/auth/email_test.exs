defmodule Viche.Auth.EmailTest do
  use ExUnit.Case, async: true

  alias Viche.Auth.Email

  describe "magic_link/2" do
    test "builds an email with the correct fields" do
      email = Email.magic_link("alice@example.com", "https://viche.ai/auth/verify?token=abc")

      assert email.to == [{"", "alice@example.com"}]
      assert email.from == {"Viche", "noreply@viche.ai"}
      assert email.subject == "Your Viche login link"
      assert email.text_body =~ "https://viche.ai/auth/verify?token=abc"
      assert email.text_body =~ "expires in 15 minutes"
    end
  end
end
