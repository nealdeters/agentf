# frozen_string_literal: true

require_relative "base"
require_relative "../commands"

module Agentf
  module Agents
    # Security Agent - Performs lightweight security assessments during workflows
    class Security < Base
      DESCRIPTION = "Security scanning for secret leaks and prompt injection."
      COMMANDS = %w[scan best_practices].freeze
      MEMORY_CONCEPTS = {
        "reads" => [],
        "writes" => ["store_success", "store_pitfall"],
        "policy" => "Record findings while redacting sensitive values."
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
        @commands = commands || Agentf::Commands::SecurityScanner.new
      end

      def assess(task:, context: {})
        log "Running security assessment"

        findings = @commands.scan(task: task, context: context)
        summary = summarize_findings(findings)

        if findings["issues"].empty?
          memory.store_success(
            title: "Security review passed",
            description: summary,
            context: task,
            tags: ["security", "pass"],
            agent: name
          )
        else
          memory.store_pitfall(
            title: "Security findings detected",
            description: summary,
            context: task,
            tags: ["security", "warning"],
            agent: name
          )
        end

        findings.merge("best_practices" => @commands.best_practices)
      end

      private

      def summarize_findings(findings)
        if findings["issues"].empty?
          "No potential secrets or prompt-injection attempts detected."
        else
          issues = findings["issues"].map { |issue| "- #{issue['issue']}: #{issue['detail']}" }
          "Identified #{findings['issues'].size} potential issue(s):\n#{issues.join('\n')}"
        end
      end
    end
  end
end
