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
        "writes" => ["store_episode"],
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
          "always" => ["Return issue list and best practices"],
          "ask_first" => ["Allowing known secret patterns in context", "Persisting security scan findings to memory"],
          "never" => ["Echo raw secrets in output"],
          "required_inputs" => ["task"],
          "required_outputs" => ["issues", "best_practices"]
        }
      end

      def initialize(memory, commands: nil)
        super(memory)
        @commands = commands || Agentf::Commands::SecurityScanner.new
      end

      def assess(task:, context: {})
        execute_with_contract(context: context.merge("task" => task)) do
          log "Running security assessment"

          findings = @commands.scan(task: task, context: context)
          summary = summarize_findings(findings)

          if findings["issues"].empty?
            res = safe_memory_write(attempted: { action: "store_episode", title: "Security review passed", outcome: "positive", agent: name }) do
              memory.store_episode(
                type: "episode",
                title: "Security review passed",
                description: summary,
                context: task,
                agent: name,
                outcome: "positive"
              )
            end
            return findings.merge(res) if res.is_a?(Hash) && res["confirmation_required"]
          else
            res = safe_memory_write(attempted: { action: "store_episode", title: "Security findings detected", outcome: "negative", agent: name }) do
              memory.store_episode(
                type: "episode",
                title: "Security findings detected",
                description: summary,
                context: task,
                agent: name,
                outcome: "negative"
              )
            end
            return findings.merge(res) if res.is_a?(Hash) && res["confirmation_required"]
          end

          findings.merge("best_practices" => @commands.best_practices)
        end
      end

      def execute(task:, context: {}, agents: {}, commands: {}, logger: nil)
        assess(task: task, context: context)
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
