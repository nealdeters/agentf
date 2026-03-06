# frozen_string_literal: true

require_relative "base"
require_relative "../commands"

module Agentf
  module Agents
    # Explorer Agent - Codebase exploration
    class Explorer < Base
      DESCRIPTION = "Rapid codebase exploration and context gathering."
      COMMANDS = %w[glob grep read_file].freeze
      MEMORY_CONCEPTS = {
        "reads" => [],
        "writes" => ["store_episode"],
        "policy" => "Store exploration breadcrumbs as episodic memories."
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

      def initialize(memory, commands: nil)
        super(memory)
        @commands = commands || Agentf::Commands::Explorer.new
      end

      def explore(query, file_pattern: nil)
        log "Exploring: #{query}"

        files = @commands.glob(query, file_types: nil)

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
