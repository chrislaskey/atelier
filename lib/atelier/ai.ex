defmodule Atelier.AI do
  @callback create_message(params :: map()) :: {:ok, map()} | {:error, term()}

  def create_message(params), do: impl().create_message(params)

  defp impl, do: Application.get_env(:atelier, :ai_client, Atelier.AI.Client)
end
