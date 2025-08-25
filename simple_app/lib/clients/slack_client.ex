defmodule SlackClient do
  @base_url "https://slack.com"
  def send_message(channel, message) do
    body = %{channel: channel, text: message}

    Req.post(client(), "/api/chat.postMessage", body)
  end

  def users() do
    Req.get(client(), url: "/api/users.list", auth: "Bearer #{token()}")
  end

  # build dynamic client based on runtime arguments
  @spec client() :: Req.client()
  def client do
    token = Application.get_env(:simple_app, :cortex_api_key)
    Req.new(base_url: @base_url, auth: {:bearer, token}, headers: basic_headers())
  end

  defp basic_headers do
    [
      {"Content-Type", "application/json"}
    ]
  end

  defp token do
    Application.get_env(:simple_app, :slack_token)
  end
end
