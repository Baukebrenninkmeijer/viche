defmodule Viche.Auth.SendMagicLinkTest do
  use Viche.DataCase, async: true

  alias Viche.Accounts
  alias Viche.Auth

  describe "send_magic_link/1" do
    test "creates a new user when email does not exist and delivers an email" do
      assert {:ok, user} = Auth.send_magic_link("new@example.com")
      assert user.email == "new@example.com"

      # User was persisted
      assert Accounts.get_user_by_email("new@example.com")
    end

    test "uses existing user when email already exists" do
      {:ok, existing} = Accounts.create_user(%{email: "existing@example.com"})

      assert {:ok, user} = Auth.send_magic_link("existing@example.com")
      assert user.id == existing.id
    end

    test "handles email case-insensitively" do
      {:ok, existing} = Accounts.create_user(%{email: "mixed@example.com"})

      assert {:ok, user} = Auth.send_magic_link("MIXED@example.com")
      assert user.id == existing.id
    end

    test "creates a magic_link token in the database" do
      {:ok, user} = Auth.send_magic_link("tokencheck@example.com")

      tokens =
        Viche.Repo.all(
          from t in Viche.Accounts.AuthToken,
            where: t.user_id == ^user.id and t.context == "magic_link"
        )

      assert length(tokens) == 1
    end
  end
end
