# frozen_string_literal: true

require_relative "base"

module Agentf
  module Agents
    # Documenter Agent - Sync Redis memory with local Markdown docs
    class Documenter < Base
      DESCRIPTION = "Syncs Redis memory with local Markdown summaries."
      COMMANDS = %w[read_file write_file memory].freeze
      MEMORY_CONCEPTS = {
        "reads" => ["get_recent_memories"],
        "writes" => [],
        "policy" => "Summarize memory trends into docs without storing raw secrets."
      }.freeze

      def self.description
        DESCRIPTION
      end

      def self.commands
        COMMANDS
      end

      def self.typed_name
        Agentf::AgentRoles::KNOWLEDGE_MANAGER
      end

      def self.when_to_use
        "Use for memory synthesis, knowledge rollups, and delivery-ready summaries."
      end

      def self.deliverables
        ["Success summary", "Pitfall summary", "Knowledge digest"]
      end

      def self.working_style
        "Concise synthesis with attention to sensitive data boundaries."
      end

      def self.memory_concepts
        MEMORY_CONCEPTS
      end

      def self.policy_boundaries
        {
          "always" => ["Summarize recent successes and pitfalls"],
          "ask_first" => ["Publishing docs to external destinations"],
          "never" => ["Leak sensitive context in summaries"],
          "required_inputs" => [],
          "required_outputs" => ["successes", "pitfalls", "total_memories"]
        }
      end

      def sync_docs(project_name)
        log "Syncing documentation"

        memories = memory.get_recent_memories(limit: 20)

        successes = memories.select { |m| m["type"] == "success" }
        pitfalls = memories.select { |m| m["type"] == "pitfall" }

        log "Found #{successes.size} successes"
        log "Found #{pitfalls.size} pitfalls"

        {
          "successes" => successes,
          "pitfalls" => pitfalls,
          "total_memories" => memories.size
        }
      end

      def execute(task:, context: {}, agents: {}, commands: {}, logger: nil)
        project = task.is_a?(String) ? task : (context["project_name"] || "project")
        sync_docs(project)
      end

    end
  end
end
