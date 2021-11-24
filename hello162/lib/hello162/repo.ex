defmodule Hello162.Repo do
  use Ecto.Repo,
    otp_app: :hello162,
    adapter: Ecto.Adapters.Postgres
end
