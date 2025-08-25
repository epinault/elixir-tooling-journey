defmodule SlackClient do
  def send_message(client, channel, message) do
    body = %{channel: channel, text: message}

    Tesla.post(client, "/api/chat.postMessage", body)
  end

  def client(token) do
    middleware = [
      {Tesla.Middleware.BaseUrl, "https://slack.com"},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.BearerAuth, token: token},
      # {Tesla.Middleware.Logger, debug: true}, # uncomment if you need to debug request
      {Tesla.Middleware.Headers,
       [
         {"User-Agent", "curl/7.64.1"}
       ]}
    ]

    Tesla.client(middleware, {Tesla.Adapter.Hackney, []})
  end
end
