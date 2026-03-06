# frozen_string_literal: true

require_relative "base"

module Agentf
  module Agents
    # Architect Agent - Strategy, task decomposition
    class Architect < Base
      DESCRIPTION = "Strategy, task decomposition, and memory retrieval."
      COMMANDS = %w[glob read_file memory].freeze
      MEMORY_CONCEPTS = {
        "reads" => ["get_recent_memories", "get_pitfalls"],
        "writes" => [],
        "policy" => "Retrieve relevant memories before planning; do not duplicate runtime memory into static markdown."
      }.freeze

      def self.description
        DESCRIPTION
      end

      def self.commands
        COMMANDS
      end

      def self.memory_concepts
        MEMORY_CONCEPTS
      end

      def plan_task(task)
        log "Planning: #{task}"

        # Retrieve relevant memories before planning
        recent = memory.get_recent_memories(limit: 5)
        pitfalls = memory.get_pitfalls(limit: 3)

        context = {
          "task" => task,
          "relevant_memories" => recent,
          "pitfalls_to_avoid" => pitfalls
        }

        # Decompose into subtasks
        subtasks = [
          { "id" => 1, "description" => "Research and gather requirements" },
          { "id" => 2, "description" => "Implement the solution" },
          { "id" => 3, "description" => "Review and test" }
        ]

        log "Found #{recent.size} relevant memories"
        log "Avoiding #{pitfalls.size} known pitfalls"
        log "Created #{subtasks.size} subtasks"

        { "subtasks" => subtasks, "context" => context }
      end
    end
  end
end
