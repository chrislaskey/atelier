defmodule Atelier.Repo do
  use Ecto.Repo,
    otp_app: :atelier,
    adapter: Ecto.Adapters.SQLite3
end
