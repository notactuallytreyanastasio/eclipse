defmodule Eclipse.Repo do
  use Ecto.Repo,
    otp_app: :eclipse,
    adapter: Ecto.Adapters.Postgres
end
