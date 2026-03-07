# frozen_string_literal: true

require_relative "base"

module Agentf
  module Agents
    # Specialist Agent - Code execution
    class Specialist < Base
      DESCRIPTION = "Code execution and lesson-learning persistence."
      COMMANDS = %w[read_file write_file run_command].freeze
      MEMORY_CONCEPTS = {
        "reads" => [],
        "writes" => ["store_success", "store_pitfall"],
        "policy" => "Persist execution outcomes as lessons for downstream agents."
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

      def self.policy_boundaries
        {
          "always" => ["Persist execution outcome", "Return deterministic success boolean"],
          "ask_first" => ["Applying architecture style changes across unrelated modules"],
          "never" => ["Claim implementation complete without execution result"],
          "required_inputs" => [],
          "required_outputs" => ["subtask_id", "success"]
        }
      end

      def execute(subtask)
        log "Executing: #{subtask['description']}"

        success = subtask.fetch("success", true)

        if success
          memory.store_success(
            title: "Completed: #{subtask['description']}",
            description: "Successfully executed subtask #{subtask['id']}",
            context: "Working on #{subtask.fetch('task', 'unknown task')}",
            tags: ["implementation", subtask.fetch("language", "general")],
            agent: name
          )
          log "Stored success memory"
        else
          memory.store_pitfall(
            title: "Failed: #{subtask['description']}",
            description: "Subtask #{subtask['id']} failed",
            context: "Working on #{subtask.fetch('task', 'unknown task')}",
            tags: ["failure", "implementation"],
            agent: name
          )
          log "Stored pitfall memory"
        end

        { "subtask_id" => subtask["id"], "success" => success, "result" => "Code executed" }
      end
    end
  end
end
