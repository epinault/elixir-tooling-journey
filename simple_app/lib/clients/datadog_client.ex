defmodule DataDogClient do
  @moduledoc """
  This is a client for the DataDog API.
  """

  @doc """
  Returns the details for the service.
  """
  @spec service_details(String.t(), map()) :: map()
  def service_details(service, opts \\ []) do
    resp =
      Req.post!(client(),
        url: "/api/v2/logs/analytics/aggregate",
        json: %{
          compute: [
            %{
              aggregation: "count"
            }
          ],
          filter: %{
            from: "now-7d",
            indexes: [
              "*"
            ],
            query: "service:#{service}*",
            to: "now"
          },
          group_by: [
            %{
              limit: 50,
              facet: "service"
            }
          ]
        }
      ).body

    {web_pods, background_pods} =
      resp["data"]["buckets"]
      |> Enum.map(fn bucket -> bucket["by"]["service"] end)
      |> Enum.reject(fn name ->
        opts[:exclude_canary] &&
          (String.ends_with?(name, "-web-canary") ||
             String.ends_with?(name, "-web-stable") ||
             String.ends_with?(name, "-500-errors") ||
             String.ends_with?(name, "-error-logs"))
      end)
      |> Enum.split_with(fn name -> String.ends_with?(name, "-web") end)

    %{
      all_services: "#{service}*",
      web_pods: web_pods,
      background_pods: background_pods
    }

    # %{
    #   all_services: "stormcrow*",
    #   web_pods: web_pods,
    #   background_pods: []
    # }
  end

  @doc """
  Returns the count of logs for the service.
  """
  @spec log_count(String.t()) :: map()
  def log_count(services) do
    query = %{
      compute: [
        %{
          aggregation: "count"
        }
      ],
      filter: %{
        from: "now-7d",
        query: build_service_query(services)
      }
    }

    log_aggregate(query)
  end

  @doc """
  Returns the count of logs by status for the service.
  """
  @spec log_count_by_status(String.t()) :: map()
  def log_count_by_status(services) do
    query = %{
      compute: [
        %{
          aggregation: "count"
        }
      ],
      filter: %{
        from: "now-7d",
        query: build_service_query(services)
      },
      group_by: [
        %{
          facet: "status"
        }
      ]
    }

    log_aggregate(query)
  end

  @doc """
  Returns the count of logs by error and services.
  """
  @spec log_count_by_error_and_services(String.t()) :: map()
  def log_count_by_error_and_services(services) do
    query = %{
      compute: [
        %{
          aggregation: "count"
        }
      ],
      filter: %{
        from: "now-7d",
        indexes: [
          "*"
        ],
        query: "status:error #{build_service_query(services)}",
        to: "now"
      },
      group_by: [
        %{
          facet: "status"
        },
        %{
          facet: "service"
        }
      ]
    }

    log_aggregate(query)
  end

  @doc """
  Returns the count of logs by status codes for the service.
  """
  @spec log_status_codes(String.t()) :: map()
  def log_status_codes(services) do
    query = %{
      compute: [
        %{
          aggregation: "count"
        }
      ],
      filter: %{
        from: "now-7d",
        indexes: [
          "*"
        ],
        query: build_service_query(services),
        to: "now"
      },
      group_by: [
        %{
          facet: "@http.status_code"
        }
      ]
    }

    log_aggregate(query)
  end

  @doc """
  Returns the logs for the service.
  """
  @spec log_pii(String.t(), String.t()) :: map()
  def log_pii(services, query) do
    resp =
      Req.post!(client(),
        url: "api/v2/logs/events/search",
        json: %{
          filter: %{
            from: "now-7d",
            query: "#{build_service_query(services)} #{query}"
          }
          # sort: "asc"
          # time: %{

          #   # "timezone": "America/Los_Angeles",
          # }
        }
      ).body

    Enum.map(resp["data"], fn event ->
      %{service: event["attributes"]["service"], message: event["attributes"]["message"]}
    end)
  end

  @doc """
  Returns the duration of the logs for the service.
  """
  @spec log_duration_p99(String.t()) :: map()
  def log_duration_p99(services) do
    Req.get!(client(),
      url: "/api/v1/query",
      params: %{
        from: seven_days_ago(),
        to: System.system_time(:second),
        query: "p99:log.duration{#{build_service_query(services)}}.rollup(43200)"
      }
    ).body
  end

  # Kubernetes Metrics

  @doc """
  Returns the CPU requests for the service.
  """
  @spec k8_cpu_requests(String.t()) :: map()
  def k8_cpu_requests(service) do
    k8_metric("min:kubernetes.cpu.requests{service:#{service}} by {container_name}.rollup(43200)")
  end

  @doc """
  Returns the CPU limits for the service.
  """
  @spec k8_cpu_limits(String.t()) :: map()
  def k8_cpu_limits(service) do
    k8_metric("min:kubernetes.cpu.limits{service:#{service}} by {container_name}.rollup(43200)")
  end

  @doc """
  Returns the CPU usage for the service.
  """
  @spec k8_cpu_usage(String.t()) :: map()
  def k8_cpu_usage(service) do
    k8_metric("max:kubernetes.cpu.usage.total{service:#{service}} by {pod_name}.rollup(43200)")
  end

  @doc """
  Returns the memory requests for the service.
  """
  @spec k8_memory_requests(String.t()) :: map()
  def k8_memory_requests(service) do
    k8_metric(
      "min:kubernetes.memory.requests{service:#{service}} by {container_name}.rollup(43200)"
    )
  end

  @doc """
  Returns the memory limits for the service.
  """
  @spec k8_memory_limits(String.t()) :: map()
  def k8_memory_limits(service) do
    k8_metric(
      "min:kubernetes.memory.limits{service:#{service}} by {container_name}.rollup(43200)"
    )
  end

  @doc """
  Returns the memory usage for the service.
  """
  @spec k8_memory_usage(String.t()) :: map()
  def k8_memory_usage(service) do
    k8_metric("max:kubernetes.memory.usage{service:#{service}} by {pod_name}.rollup(43200)")
  end

  @doc """
  Returns the pod restarted for the service.
  """
  @spec k8_pod_restarted(String.t()) :: map()
  def k8_pod_restarted(service) do
    k8_metric(
      "default_zero(avg:kubernetes.containers.state.terminated{env:prod-usw2,service::#{service}} by {reason})"
    )
  end

  # SLO Metrics

  @doc """
  Returns the SLOs for the service.
  """
  @spec slos(String.t()) :: map()
  def slos(service) do
    Req.get!(client(), url: "/api/v1/slo/search", params: %{query: "service:#{service}"}).body
  end

  # Helper Functions

  @doc """
  Builds the service query for the service.
  """
  @spec build_service_query(String.t() | [String.t()]) :: String.t()
  def build_service_query(services) do
    services = if is_binary(services), do: [services], else: services

    Enum.map_join(services, " OR ", fn service -> "service:#{service}" end)
  end

  defp k8_metric(query) do
    Req.get!(client(),
      url: "/api/v1/query",
      params: %{
        from: seven_days_ago(),
        to: System.system_time(:second),
        query: query
      }
    ).body
  end

  defp log_aggregate(query) do
    Req.post!(client(),
      url: "/api/v2/logs/analytics/aggregate",
      json: query
    ).body
  end

  # build dynamic client based on runtime arguments
  @spec client() :: Req.client()
  def client do
    Req.new(
      base_url: "https://example.com",
      headers: [
        {"DD-API-KEY", Application.get_env(:simple_app, :datadog_api_key)},
        {"DD-APPLICATION-KEY", Application.get_env(:simple_app, :datadog_application_key)}
      ]
    )
  end

  defp seven_days_ago do
    System.system_time(:second) - 7 * 86_400
  end
end
