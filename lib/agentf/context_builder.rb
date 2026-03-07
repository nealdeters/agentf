# frozen_string_literal: true

module Agentf
  class ContextBuilder
    def initialize(memory:)
      @memory = memory
    end

    def build(agent:, workflow_state:, limit: 8)
      task_type = workflow_state["workflow_type"]
      task = workflow_state["task"]

      @memory.get_agent_context(
        agent: agent,
        task_type: task_type,
        query_embedding: simple_embedding(task),
        limit: limit
      )
    rescue StandardError
      { "agent" => agent, "intent" => [], "memories" => [], "similar_tasks" => [] }
    end

    private

    def simple_embedding(text)
      normalized = text.to_s.downcase
      [
        normalized.include?("fix") || normalized.include?("bug") ? 1.0 : 0.0,
        normalized.include?("feature") || normalized.include?("add") ? 1.0 : 0.0,
        normalized.include?("security") ? 1.0 : 0.0,
        normalized.length.to_f / 100.0
      ]
    end
  end
end
