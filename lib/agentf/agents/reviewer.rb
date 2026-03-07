# frozen_string_literal: true

require_relative "base"

module Agentf
  module Agents
    # Reviewer Agent - Quality assurance
    class Reviewer < Base
      DESCRIPTION = "Quality assurance and regression checking against memory."
      COMMANDS = %w[read_file memory].freeze
      MEMORY_CONCEPTS = {
        "reads" => ["get_pitfalls", "get_recent_memories"],
        "writes" => [],
        "policy" => "Validate outputs against known pitfalls before approval."
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
          "always" => ["Report approval decision", "Highlight known pitfalls in review findings"],
          "ask_first" => ["Approving with unresolved critical security issues"],
          "never" => ["Approve without any review evidence"],
          "required_inputs" => [],
          "required_outputs" => ["approved", "issues"]
        }
      end

      def review(subtask_result)
        log "Reviewing subtask #{subtask_result['subtask_id']}"

        pitfalls = memory.get_pitfalls(limit: 5)
        memories = memory.get_recent_memories(limit: 5)

        issues = []

        pitfalls.each do |pitfall|
          issues << "Warning: Known pitfall - #{pitfall['title']}" if pitfall["type"] == "pitfall"
        end

        approved = issues.empty?

        if approved
          log "Approved (no issues found)"
        else
          log "Issues found: #{issues.size}"
          issues.each { |issue| log "  - #{issue}" }
        end

        { "approved" => approved, "issues" => issues }
      end
    end
  end
end
