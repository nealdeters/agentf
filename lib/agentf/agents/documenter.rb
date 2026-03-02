# frozen_string_literal: true

require_relative "base"

module Agentf
  module Agents
    # Documenter Agent - Sync Redis memory with local Markdown docs
    class Documenter < Base
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
    end
  end
end
