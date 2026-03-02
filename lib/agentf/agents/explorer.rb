# frozen_string_literal: true

require_relative "base"
require_relative "../tools/explorer"

module Agentf
  module Agents
    # Explorer Agent - Codebase exploration
    class Explorer < Base
      def initialize(memory, tools: nil)
        super(memory)
        @tools = tools || Agentf::Tools::Explorer.new
      end

      def explore(query, file_pattern: nil)
        log "Exploring: #{query}"

        files = @tools.glob(query, file_types: nil)

        memory.store_episode(
          type: "exploration",
          title: "Explored: #{query}",
          description: "Found #{files.size} relevant files",
          context: "Search pattern: #{file_pattern || 'all files'}",
          tags: ["exploration", "context"],
          agent: name
        )

        log "Found #{files.size} files"

        { "query" => query, "files" => files, "context_gathered" => true }
      end
    end
  end
end
