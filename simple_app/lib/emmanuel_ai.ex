defmodule SimpleApp do
  @moduledoc """
  Documentation for `EmmanuelAi`.
  """

  def schedule_agents(opts \\ []) do
    services = CortexClient.all_services()

    services_to_verify =
      case Keyword.get(opts, :service_only) do
        nil ->
          services["entities"]

        service_only ->
          Enum.filter(services["entities"], fn service -> service["tag"] in service_only end)
      end

    verifiers =
      case Keyword.get(opts, :verifiers) do
        nil -> [:playbook, :cortex_link]
        verifiers -> verifiers
      end

    dbg(services_to_verify)
    dbg(verifiers)

    Enum.each(verifiers, fn verifier ->
      case verifier do
        :playbook ->
          schedule_playbook_verifier(services_to_verify)

        :cortex_link ->
          schedule_cortex_link_verifier(services_to_verify)
      end
    end)

    :ok
  end

  def schedule_playbook_verifier(services) do
    services
    |> Enum.map(fn service ->
      EmmanuelAi.Workers.PlaybookVerifier.new(%{
        name: service["name"],
        links: service["links"]
      })
    end)
    |> Oban.insert_all()

    File.mkdir_p!(Path.join(["tmp", "playbook_verification"]))
  end

  def schedule_cortex_link_verifier(services) do
    services
    |> Enum.map(fn service ->
      EmmanuelAi.Workers.CortexLinkVerifier.new(%{
        name: service["name"],
        links: service["links"]
      })
    end)
    |> Oban.insert_all()

    File.mkdir_p!(Path.join(["tmp", "cortex_link_verification"]))
  end
end
