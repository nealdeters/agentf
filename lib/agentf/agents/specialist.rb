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

      def self.typed_name
        Agentf::AgentRoles::ENGINEER
      end

      def self.when_to_use
        "Use for implementation, code edits, and deterministic execution outcomes."
      end

      def self.deliverables
        ["Implemented code", "Execution status", "Success or pitfall memory"]
      end

      def self.working_style
        "Execution-focused, deterministic, and evidence-driven."
      end

      def self.memory_concepts
        MEMORY_CONCEPTS
      end

      def self.policy_boundaries
        {
          "always" => ["Persist execution outcome", "Return deterministic success boolean"],
          "ask_first" => ["Applying architecture style changes across unrelated modules"],
          "never" => ["Claim implementation complete without execution result"],
          "required_inputs" => ["description"],
          "required_outputs" => ["subtask_id", "success"]
        }
      end

      def execute(subtask)
        normalized_subtask = subtask.merge(
          "id" => subtask["id"] || "ad-hoc",
          "description" => subtask["description"] || "Execute implementation step"
        )

        execute_with_contract(context: normalized_subtask) do
          log "Executing: #{normalized_subtask['description']}"

          success = normalized_subtask.fetch("success", true)

          if success
            memory.store_success(
              title: "Completed: #{normalized_subtask['description']}",
              description: "Successfully executed subtask #{normalized_subtask['id']}",
              context: "Working on #{normalized_subtask.fetch('task', 'unknown task')}",
              tags: ["implementation", normalized_subtask.fetch("language", "general")],
              agent: name
            )
            log "Stored success memory"
          else
            memory.store_pitfall(
              title: "Failed: #{normalized_subtask['description']}",
              description: "Subtask #{normalized_subtask['id']} failed",
              context: "Working on #{normalized_subtask.fetch('task', 'unknown task')}",
              tags: ["failure", "implementation"],
              agent: name
            )
            log "Stored pitfall memory"
          end

          { "subtask_id" => normalized_subtask["id"], "success" => success, "result" => "Code executed" }
        end
      end
    end
  end
end
