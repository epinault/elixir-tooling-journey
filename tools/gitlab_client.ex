defmodule GitlabClient do
  def project_details(client, repo_path) when is_binary(repo_path) do
    Tesla.get(client, "/api/v4/projects/engineering%2F#{URI.encode_www_form(repo_path)}")
  end

  def project_detail_by_id(client, id) do
    Tesla.get(client, "/api/v4/projects/#{id}")
  end

  def list_approval_rules(client, project_id) do
    Tesla.get(client, "/api/v4/projects/#{project_id}/approval_rules")
  end

  def get_protected_branch(client, project_id, branch) do
    Tesla.get(client, "/api/v4/projects/#{project_id}/protected_branches/#{branch}")
  end

  def update_project(client, project_id, project_details) do
    Tesla.put(client, "/api/v4/projects/#{project_id}", project_details)
  end

  def rebase_mr(client, project_id, merge_request_id) do
    Tesla.put(
      client,
      "/api/v4/projects/#{project_id}/merge_requests/#{merge_request_id}/rebase",
      %{}
    )
  end

  def merge_mr(client, project_id, merge_request_id) do
    Tesla.put(
      client,
      "/api/v4/projects/#{project_id}/merge_requests/#{merge_request_id}/merge",
      %{}
    )
  end

  def update_protected_branch(client, project_id, branch, details) do
    Tesla.patch(client, "/api/v4/projects/#{project_id}/protected_branches/#{branch}", details)
  end

  def update_approval_rule(client, project_id, rule_id, rule_details) do
    Tesla.put(client, "/api/v4/projects/#{project_id}/approval_rules/#{rule_id}", rule_details)
  end

  def list_projects(client, state \\ [], page \\ 1, page_limit \\ 100) do
    with {:ok, %{status: 200, body: body}} <-
           Tesla.get(
             client,
             "/api/v4/projects?archived=false&page=#{page}&page_limit=#{page_limit}"
           ) do
      page_state =
        Enum.reduce(body, [], fn project, acc ->
          path = project["path_with_namespace"]

          if String.starts_with?(path, "engineering") && !String.contains?(path, "github-mirrors") do
            [String.replace(path, "engineering/", "") | acc]
          else
            acc
          end
        end)

      if Enum.empty?(body) do
        {:ok, state}
      else
        final_state =
          if is_nil(state) do
            page_state
          else
            state ++ page_state
          end

        list_projects(client, final_state, page + 1)
      end
    end
  end

  def list_merge_requests(client, details \\ []) do
    Tesla.get(
      client,
      "/api/v4/merge_requests",
      query: details
    )
  end

  def list_merge_requests(client, project_id, details) do
    Tesla.get(
      client,
      "/api/v4/projects/#{project_id}/merge_requests",
      query: details
    )
  end

  def get_merge_request(client, project_id, merge_request_id, details \\ []) do
    Tesla.get(
      client,
      "/api/v4/projects/#{project_id}/merge_requests/#{merge_request_id}",
      query: details
    )
  end

  def create_mr(client, project_id, details) do
    body = Jason.encode!(details)

    Tesla.post(client, "/api/v4/projects/#{project_id}/merge_requests", body,
      headers: [{"Content-Type", "application/json"}, {"Accept", "*/*"}]
    )
  end

  def check_file_exists(client, project_id, path) do
    Tesla.get(
      client,
      "/api/v4/projects/#{project_id}/repository/files/#{URI.encode_www_form(path)}?ref=master"
    )
  end

  # build dynamic client based on runtime arguments
  def client(token) do
    middleware = [
      {Tesla.Middleware.BaseUrl, "https://example.com"},
      Tesla.Middleware.JSON,
      # {Tesla.Middleware.Logger, debug: true}, # uncomment if you need to debug request
      {Tesla.Middleware.Headers,
       [
         {"User-Agent", "curl/7.64.1"},
         {"PRIVATE-TOKEN", token},
         {"Content-Type", "application/json"},
         {"Accept", "*/*"}
       ]},
      {Tesla.Middleware.Retry,
       should_retry: fn
         {:ok, %{status: status}} -> status == 500
         {:error, _} -> true
       end,
       delay: 500,
       max_attempts: 3,
       max_delay: 10_000,
       backoff: :exponential,
       backoff_factor: 2,
       backoff_jitter: 0.5}
    ]

    Tesla.client(middleware, {Tesla.Adapter.Hackney, []})
  end
end
