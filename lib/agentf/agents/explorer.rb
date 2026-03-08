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

      def self.typed_name
        Agentf::AgentRoles::RESEARCHER
      end

      def self.when_to_use
        "Use for codebase discovery, evidence gathering, and dependency tracing."
      end

      def self.deliverables
        ["Relevant file list", "Search evidence", "Context breadcrumbs"]
      end

      def self.working_style
        "Fast exploration with concrete references and traceable findings."
      end

      def self.memory_concepts
        MEMORY_CONCEPTS
      end

      def self.policy_boundaries
        {
          "always" => ["Return concrete file evidence", "Persist exploration breadcrumbs"],
          "ask_first" => ["Scanning outside configured base path"],
          "never" => ["Mutate project files during exploration"],
          "required_inputs" => [],
          "required_outputs" => ["files", "context_gathered"]
        }
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
