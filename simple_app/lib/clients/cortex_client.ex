defmodule CortexClient do
  @moduledoc """
  This is a client for the Cortex API.
  """
  @base_url "https://api.getcortexapp.com/api/v1"

  @doc """
  Returns the scorecard scores for the service.
  """
  @spec service_scores(String.t()) :: map()
  def service_scores(service_tag) do
    Req.get!(client(), url: "scorecards/all/scores", params: %{"entityTag" => service_tag}).body
  end

  @doc """
  Returns the next steps for the service.
  """
  @spec next_steps(String.t()) :: map()
  def next_steps(service_tag) do
    Req.get!(client(), url: "scorecards/all/next-steps", params: %{"entityTag" => service_tag}).body
  end

  @doc """
  Returns the metadata for the service.
  """
  @spec metadata(String.t()) :: map()
  def metadata(service_tag) do
    Req.get!(client(), url: "/catalog/:service", path_params: [service: service_tag]).body[
      "metadata"
    ]
  end

  @doc """
  Returns the details for the service.
  """
  @spec service_details(String.t()) :: map()
  def service_details(service_name) do
    entities =
      Req.get!(client(),
        url: "/catalog",
        params: %{
          "groups" => "kind:service",
          "types" => "service",
          "query" => "name:#{service_name}",
          "pageSize" => 5,
          "page" => 0
        }
      ).body["entities"]

    # Search in cortex is dumb, so we need to find the closest match
    entity =
      Enum.max_by(entities, fn entity -> String.jaro_distance(entity["name"], service_name) end)

    %{
      cortex_name: entity["name"],
      cortex_tag: entity["tag"],
      cortex_repo: entity["git"]["repositoryUrl"],
      cortex_entity_id: entity["id"]
    }
  end

  @doc """
  Returns the search for the service matching the name.
  """
  @spec service_search_by_name(String.t()) :: map()
  def service_search_by_name(service_name) do
    Req.get!(client(),
      url: "/catalog",
      params: %{
        "groups" => "kind:service",
        "types" => "service",
        "query" => "name:#{service_name}",
        "pageSize" => 5,
        "page" => 0
      }
    ).body
  end

  @doc """
  Returns all services playbook links for each service.
  """
  @spec services_playbook() :: map()
  def services_playbook do
    Enum.map(all_services(page_size: 10), fn service ->
      dbg(service)
      service_details(service["name"])
    end)
  end

  @doc """
  Returns all services available in Cortex.
  """
  @spec all_services() :: map()
  def all_services(opts \\ []) do
    Req.get!(client(),
      url: "/catalog",
      params: %{
        "groups" => Keyword.get(opts, :groups, "kind:service"),
        "types" => Keyword.get(opts, :types, "service"),
        "pageSize" => Keyword.get(opts, :page_size, 500),
        "page" => Keyword.get(opts, :page, 0),
        "includeLinks" => true
      }
    ).body
  end

  # build dynamic client based on runtime arguments
  @spec client() :: Req.client()
  def client do
    token = Application.get_env(:simple_app, :cortex_api_key)
    Req.new(base_url: @base_url, auth: {:bearer, token})
  end
end
