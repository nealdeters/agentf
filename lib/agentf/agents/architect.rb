# frozen_string_literal: true

require_relative "base"

module Agentf
  module Agents
    # Architect Agent - Strategy, task decomposition
    class Architect < Base
      DESCRIPTION = "Strategy, task decomposition, and memory retrieval."
      COMMANDS = %w[glob read_file memory].freeze
      MEMORY_CONCEPTS = {
        "reads" => ["get_recent_memories", "get_episodes"],
        "writes" => [],
        "policy" => "Retrieve relevant memories before planning; do not duplicate runtime memory into static markdown."
      }.freeze

      def self.description
        DESCRIPTION
      end

      def self.commands
        COMMANDS
      end

      def self.typed_name
        Agentf::AgentRoles::PLANNER
      end

      def self.when_to_use
        "Use for planning, decomposition, and constraints mapping before implementation."
      end

      def self.deliverables
        ["Execution plan", "Decomposed subtasks", "Risk and pitfall notes"]
      end

      def self.working_style
        "Strategic and constraint-aware with explicit decomposition."
      end

      def self.memory_concepts
        MEMORY_CONCEPTS
      end

      def self.policy_boundaries
        {
          "always" => ["Capture constraints before decomposition", "Use recent memories and negative episodes in planning"],
          "ask_first" => ["Changing architectural style from project defaults"],
          "never" => ["Skip task decomposition for non-trivial workflows"],
          "required_inputs" => [],
          "required_outputs" => ["subtasks", "context"]
        }
      end

      def plan_task(task)
        log "Planning: #{task}"

        # Retrieve relevant memories before planning
        recent = memory.get_recent_memories(limit: 5)
        pitfalls = memory.get_episodes(limit: 3, outcome: "negative")

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

      def execute(task:, context: {}, agents: {}, commands: {}, logger: nil)
        plan_task(task)
      end
    end
  end
end
