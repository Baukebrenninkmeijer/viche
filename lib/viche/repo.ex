defmodule Viche.Repo do
  use Ecto.Repo,
    otp_app: :viche,
    adapter: Ecto.Adapters.Postgres
end
