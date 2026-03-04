ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Atelier.Repo, :manual)
Mox.defmock(Atelier.AI.MockClient, for: Atelier.AI)
