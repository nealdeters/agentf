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

      def self.typed_name
        Agentf::AgentRoles::SECURITY_REVIEWER
      end

      def self.when_to_use
        "Use for security gating, prompt-injection checks, and secret leak detection."
      end

      def self.deliverables
        ["Security findings", "Best-practice checklist", "Pass/warn outcome"]
      end

      def self.working_style
        "Risk-focused with redaction-safe reporting."
      end

      def self.memory_concepts
        MEMORY_CONCEPTS
      end

      def self.policy_boundaries
        {
          "always" => ["Return issue list and best practices", "Persist outcome as success or pitfall"],
          "ask_first" => ["Allowing known secret patterns in context"],
          "never" => ["Echo raw secrets in output"],
          "required_inputs" => [],
          "required_outputs" => ["issues", "best_practices"]
        }
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
