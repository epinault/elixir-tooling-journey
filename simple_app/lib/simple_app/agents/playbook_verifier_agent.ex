defmodule SimpleApp.Agents.PlaybookVerifierAgent do
  @moduledoc """
  This is an agent that will verify the playbook for a service.
  """

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Function
  alias LangChain.FunctionParam
  alias LangChain.Message

  @doc """
  Returns the name of the agent.
  """
  @spec name() :: String.t()
  def name do
    "Playbook Verifier"
  end

  @doc """
  Creates an agent.
  """
  @spec create_agent(map()) :: LLMChain.t()
  def create_agent(context) do
    # Create an LLM instance
    llm =
      ChatOpenAI.new!(%{
        model: "gpt-4o-mini",
        temperature: 0
      })

    dbg(context)

    # Create a prompt template
    template = """
    You are an expert playbook verifier specializing in verifying playbooks for services.
    Your task is to verify the playbook for a service. The service name should be found in the title of the page.

    When analyzing a playbook, look specifically for:

    1. Check if the playbook has the runbooks and operations reviews as children page of the current page.
    2. it has an architecture section
      - It has a link to architecture docs section for that service.
      - The link should be prefixed with https://example.com/engineering/
      - service name should be present in the link (case insensitive, typo allowed)
    3. it has a customer interactions section
      - It has a list of customer interactions in a table.
      - Each row must contain at least the name, a brief description, and the tier level associated
    4. It has a runbooks section
      - It has a list of runbooks
      - Each runbook should be a link to a confluence page.
      - The link to the runbook should be prefixed with https://example.com/wiki/spaces/EN
    5. It has an operations reviews section
      - It has a list of operations reviews
      - Each runbook should be a link to a confluence page.
      - The link to the runbook should be prefixed with https://example.com/wiki/spaces/EN
      - Identify if there was any missed operations review. Each of them has the date in the title. Operation reviews are expected to be bi-weekly at a minimum. Mention any gaps in the last 3 months only.
    6. It has a dashboards section
      - It has a list of dashboards
      - Each dashboard should be a link to a datadog dashboard.
      - The link to the dashboard should be prefixed with https://app.datadoghq.com/dashboard
    7. It has a workers section
      - It has a list of workers in a table.
      - Each row must contain at least the name, a brief description. Optionally, it can contain the tier level associated

    Please be thorough in your analysis and flag any deviation from the expected format.

    Here is the expected output format in the correct order:

    ## Summary

    - Playbook link: [Replace with the link to the playbook]
    - Architecture link: [Replace with the link to the architecture]
    - Runbooks: [Replace with the list of runbooks]
    - Operations reviews: [Replace with the list of operations reviews in reverse order but limit to the most recent 4 reviews]
    - Is the playbook complete? if not, mention which section needs work
    - Is the structure of the playbook correct?

    If there are no issues for a section, then just use the simpler following format:

    ## Findings for [section name]
    - ✅ Looks good!

    If there are issues, then use the following output format:

    ## Findings for [section name]
    - [Replace this line with a list of findings]

    ## Recommendations
    - [Replace this line with a list of recommendations]
    """

    # Create the chain
    %{
      llm: llm,
      verbose: Map.get(context, :verbose, true)
    }
    |> LLMChain.new!()
    |> LLMChain.add_message(Message.new_system!(template))
  end

  @doc """
  Returns the page content function.
  """
  @spec get_page_content() :: LangChain.Function.t()
  def get_page_content do
    Function.new!(%{
      name: "get_page_content",
      parameters: [
        FunctionParam.new!(%{name: "page_id", type: :string, required: true}),
        FunctionParam.new!(%{name: "service", type: :string, required: true})
      ],
      description: "Return the page content for the page specified by its id",
      function: fn args, _context ->
        res = ConfluenceClient.get_page_content(args["page_id"])

        File.write!(
          "tmp/playbook_verification/#{args["service"]}_#{args["page_id"]}.md",
          res
        )

        {:ok, res}
      end
    })
  end

  @doc """
  Returns the page children function.
  """
  @spec get_page_children() :: LangChain.Function.t()
  def get_page_children do
    Function.new!(%{
      name: "get_page_children",
      parameters: [
        FunctionParam.new!(%{name: "page_id", type: :string, required: true})
      ],
      description: "Return JSON object of the page children for the page specified by its id",
      function: fn args, _context ->
        {:ok, Jason.encode!(ConfluenceClient.get_page_children(args["page_id"]))}
      end
    })
  end

  @doc """
  Chat with the specified agent.
  """
  @spec chat(LLMChain.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def chat(agent, input) do
    agent
    |> LLMChain.add_message(Message.new_user!(input))
    |> LLMChain.add_tools([
      get_page_content(),
      get_page_children()
    ])
    |> LLMChain.run(
      input: input,
      mode: :while_needs_response
    )
  end

  @doc """
  Chat with the default agent.
  """
  @spec chat_with_default_agent(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def chat_with_default_agent(input, context \\ %{}) do
    agent = create_agent(context)
    chat(agent, input)
  end
end
