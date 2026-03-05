defmodule Atelier.AI.Client do
  @behaviour Atelier.AI

  @url "https://api.anthropic.com/v1/messages"

  @impl true
  def create_message(params) do
    case Req.post(@url,
           headers: headers(),
           json: params,
           retry: :transient,
           receive_timeout: 300_000
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp headers do
    [
      {"x-api-key", api_key()},
      {"anthropic-version", "2023-06-01"}
    ]
  end

  defp api_key do
    Application.get_env(:atelier, :anthropic_api_key) ||
      raise "Missing :anthropic_api_key config. Set the ANTHROPIC_API_KEY environment variable."
  end
end
