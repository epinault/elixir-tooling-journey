defmodule CortexClient do
  def list_entities(client) do
    with {:ok, %{status: 200, body: body}} <-
           Tesla.get(client, "/api/v1/catalog", query: [types: "service"]) do
      {:ok, body}
    end
  end

  # build dynamic client based on runtime arguments
  def client(token) do
    middleware = [
      {Tesla.Middleware.BaseUrl, "https://api.getcortexapp.com"},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.BearerAuth, token: token}
      # uncomment if you need to debug request
      # {Tesla.Middleware.Logger, debug: true}
    ]

    Tesla.client(middleware, {Tesla.Adapter.Hackney, []})
  end
end
