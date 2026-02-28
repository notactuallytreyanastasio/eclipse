defmodule Illuminates.Repo do
  use Ecto.Repo,
    otp_app: :illuminates,
    adapter: Ecto.Adapters.Postgres
end
