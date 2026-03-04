defmodule Atelier.AITest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  describe "create_message/1" do
    test "dispatches to the configured client and returns the response" do
      response = %{
        "id" => "msg_123",
        "type" => "message",
        "role" => "assistant",
        "content" => [%{"type" => "text", "text" => "Hello!"}],
        "model" => "claude-sonnet-4-6",
        "stop_reason" => "end_turn",
        "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
      }

      Atelier.AI.MockClient
      |> expect(:create_message, fn params ->
        assert params.model == "claude-sonnet-4-6"
        assert is_list(params.messages)
        {:ok, response}
      end)

      assert {:ok, ^response} =
               Atelier.AI.create_message(%{
                 model: "claude-sonnet-4-6",
                 max_tokens: 4096,
                 messages: [%{role: "user", content: "Hello"}]
               })
    end

    test "returns error on failure" do
      Atelier.AI.MockClient
      |> expect(:create_message, fn _params ->
        {:error, %{status: 401, body: %{"error" => "invalid_api_key"}}}
      end)

      assert {:error, %{status: 401}} = Atelier.AI.create_message(%{messages: []})
    end
  end
end
