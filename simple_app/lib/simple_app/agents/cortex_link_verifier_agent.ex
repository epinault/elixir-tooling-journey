defmodule SimpleApp.Agents.CortexLinkVerifierAgent do
  @moduledoc """
  This agent verifies the links in the Cortex service.
  """

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Message

  def name do
    "Cortex Link Verifier"
  end

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
    You are an expert verifying Cortex information stored for a service.
    Your task is to verify that the link are correct.

    The service name is #{context["name"]}.

    The links are #{Jason.encode!(context["links"])}.

    Correctness is defined as

    1. the link being able to be clicked and navigated to.
    2. the link being the correct link for the service.
    3. If this is monitoring related link, it must point to Datadog. Any others are not allowed.
    4. If this is a runbook link, it must point to Confluence. Any others are not allowed.

    Please be thorough in your analysis and flag any deviation. Output the results in the following format:

    ## Summary

    - [Link Name]([Link URL]): [✅ Looks good! | ❌ Looks bad!]
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
  Chat with the specified agent.
  """
  @spec chat(LLMChain.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def chat(agent, input) do
    agent
    |> LLMChain.add_message(Message.new_user!(input))
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
