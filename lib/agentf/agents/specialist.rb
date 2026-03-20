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
        "writes" => ["store_episode"],
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
          "ask_first" => ["Applying architecture style changes across unrelated modules", "Persisting execution outcomes to memory (success/pitfall)"] ,
          "never" => ["Claim implementation complete without execution result"],
          "required_inputs" => ["description"],
          "required_outputs" => ["subtask_id", "success"]
        }
      end

      def execute(task:, context: {}, agents: {}, commands: {}, logger: nil)
        subtask = task.is_a?(Hash) ? task : (context["current_subtask"] || { "description" => task })

        normalized_subtask = subtask.merge(
          "id" => subtask["id"] || "ad-hoc",
          "description" => subtask["description"] || "Execute implementation step"
        )

        execute_with_contract(context: normalized_subtask) do
          log "Executing: #{normalized_subtask['description']}"

          success = normalized_subtask.fetch("success", true)

          if success
            res = safe_memory_write(attempted: { action: "store_episode", title: "Completed: #{normalized_subtask['description']}", outcome: "positive", agent: name }) do
              memory.store_episode(
                type: "episode",
                title: "Completed: #{normalized_subtask['description']}",
                description: "Successfully executed subtask #{normalized_subtask['id']}",
                context: "Working on #{normalized_subtask.fetch('task', 'unknown task')}",
                agent: name,
                outcome: "positive"
              )
            end

            if res.is_a?(Hash) && res["confirmation_required"]
              log "Memory confirmation required when storing success: #{res['confirmation_details'].inspect}"
              return { "subtask_id" => normalized_subtask["id"], "success" => success, "result" => "Code executed", "confirmation_required" => true, "confirmation_details" => res["confirmation_details"], "attempted" => res["attempted"] }
            end
          else
            res = safe_memory_write(attempted: { action: "store_episode", title: "Failed: #{normalized_subtask['description']}", outcome: "negative", agent: name }) do
              memory.store_episode(
                type: "episode",
                title: "Failed: #{normalized_subtask['description']}",
                description: "Subtask #{normalized_subtask['id']} failed",
                context: "Working on #{normalized_subtask.fetch('task', 'unknown task')}",
                agent: name,
                outcome: "negative"
              )
            end

            if res.is_a?(Hash) && res["confirmation_required"]
              log "Memory confirmation required when storing pitfall: #{res['confirmation_details'].inspect}"
              return { "subtask_id" => normalized_subtask["id"], "success" => success, "result" => "Code executed", "confirmation_required" => true, "confirmation_details" => res["confirmation_details"], "attempted" => res["attempted"] }
            end
          end

          { "subtask_id" => normalized_subtask["id"], "success" => success, "result" => "Code executed" }
        end
      end
    end
  end
end
