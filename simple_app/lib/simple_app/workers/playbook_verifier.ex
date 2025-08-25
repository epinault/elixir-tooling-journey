defmodule SimpleApp.Workers.PlaybookVerifier do
  use Oban.Worker, queue: :default

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) ::
          :ok
          | {:error, atom() | <<_::176>>}
          | {:error, LangChain.Chains.LLMChain.t(), LangChain.LangChainError.t()}
  def perform(%Oban.Job{args: args}) do
    name = String.downcase(args["name"])

    with {:ok, page_id} <- get_page_id_from_url(args["links"]),
         {:ok, response} <-
           SimpleApp.Agents.PlaybookVerifierAgent.chat_with_default_agent(
             "Verify the playbook for #{name} with the page id: #{page_id}"
           ) do
      file_path = Path.join(["tmp", "playbook_verification", "#{name}.md"])

      File.write(file_path, response.last_message.content)
    end
  end

  defp get_page_id_from_url(urls) do
    if link = find_playbook_link(urls) do
      {page_id, _} =
        link["url"]
        |> String.split("/")
        |> List.pop_at(-2)

      {:ok, page_id}
    else
      {:error, "No playbook link found"}
    end
  end

  defp find_playbook_link(links) do
    links
    |> Enum.find(fn link -> link["type"] == "runbook" end)
  end
end
