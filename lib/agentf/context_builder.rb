# frozen_string_literal: true

module Agentf
  class ContextBuilder
    def initialize(memory:, embedding_provider: Agentf::EmbeddingProvider.new)
      @memory = memory
      @embedding_provider = embedding_provider
    end

    def build(agent:, workflow_state:, limit: 8)
      task_type = workflow_state["workflow_type"]
      task = workflow_state["task"]

      @memory.get_agent_context(
        agent: agent,
        task_type: task_type,
        query_text: task,
        query_embedding: @embedding_provider.embed(task),
        limit: limit
      )
    rescue StandardError
      { "agent" => agent, "intent" => [], "memories" => [], "similar_tasks" => [] }
    end
  end
end
