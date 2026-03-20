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
        "writes" => ["store_lesson"],
        "policy" => "Store research findings as lessons after user confirmation."
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
          "always" => ["Return concrete file evidence"],
          "ask_first" => ["Scanning outside configured base path", "Persisting research lessons to memory"],
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

        res = safe_memory_write(attempted: { action: "store_lesson", title: "Research finding: #{query}", agent: name }) do
          memory.store_lesson(
            title: "Research finding: #{query}",
            description: "Found #{files.size} relevant files during exploration",
            context: "Search pattern: #{file_pattern || 'all files'}",
            agent: name
          )
        end

        if res.is_a?(Hash) && res["confirmation_required"]
          log "Memory confirmation required during exploration: #{res['confirmation_details'].inspect}"
          return {
            "files" => files,
            "context_gathered" => true,
            "confirmation_required" => true,
            "confirmation_details" => res["confirmation_details"],
            "attempted" => res["attempted"],
            "confirmed_write_token" => res["confirmed_write_token"],
            "confirmation_prompt" => res["confirmation_prompt"]
          }
        end

        log "Found #{files.size} files"

        { "query" => query, "files" => files, "context_gathered" => true }
      end

      def execute(task:, context: {}, agents: {}, commands: {}, logger: nil)
        query = context["explore_query"] || task || "*.rb"
        explore(query, file_pattern: context["file_pattern"])
      end
    end
  end
end
