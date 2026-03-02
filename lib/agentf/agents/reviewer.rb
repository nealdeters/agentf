# frozen_string_literal: true

require_relative "base"

module Agentf
  module Agents
    # Reviewer Agent - Quality assurance
    class Reviewer < Base
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
