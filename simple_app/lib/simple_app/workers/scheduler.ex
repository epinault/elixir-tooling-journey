defmodule SimpleApp.Workers.Scheduler do
  use Oban.Worker, queue: :scheduled

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    SimpleApp.schedule_agents()
  end
end
