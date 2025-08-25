defmodule SimpleApp.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      SimpleApp.Repo,
      {Oban, Application.fetch_env!(:simple_app, Oban)},
      {DynamicSupervisor, strategy: :one_for_one, name: SimpleApp.DynamicSupervisor},
      {Task.Supervisor, name: SimpleApp.AgentTaskSupervisor}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SimpleApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
