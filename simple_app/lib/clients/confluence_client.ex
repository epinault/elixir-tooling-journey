defmodule ConfluenceClient do
  @moduledoc false
  @base_url "https://example.com/wiki/api/v2"

  @doc """
  Get a page from Confluence.
  """
  def get_page(page_id, opts \\ []) do
    Req.get!(
      client(),
      url: "/pages/#{page_id}?body-format=#{opts[:view]}",
      headers: basic_headers()
    ).body
  end

  def get_page_content(page_id, opts \\ []) do
    view = Keyword.get(opts, :view, "view")

    get_page(page_id, view: view)
    |> Map.get("body")
    |> Map.get(view)
    |> Map.get("value")
  end

  @doc """
  Get the children of a page.
  """
  def get_page_children(page_id) do
    Req.get!(
      client(),
      url: "/pages/#{page_id}/children",
      headers: basic_headers()
    ).body
  end

  @doc """
  Build dynamic client based on runtime arguments
  """
  def client do
    Req.new(base_url: @base_url, headers: basic_headers())
  end

  defp basic_headers do
    [
      {"Authorization", "Basic #{encoded_confluence_token()}"},
      {"Content-Type", "application/json"}
    ]
  end

  defp encoded_confluence_token do
    token =
      Application.get_env(
        :simple_app,
        :confluence_api_key
      )

    user =
      Application.get_env(
        :simple_app,
        :confluence_user
      )

    Base.encode64("#{user}:#{token}")
  end
end
