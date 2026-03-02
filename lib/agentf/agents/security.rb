# frozen_string_literal: true

require_relative "base"
require_relative "../tools/security_scanner"

module Agentf
  module Agents
    # Security Agent - Performs lightweight security assessments during workflows
    class Security < Base
      def initialize(memory, tools: nil)
        super(memory)
        @tools = tools || Agentf::Tools::SecurityScanner.new
      end

      def assess(task:, context: {})
        log "Running security assessment"

        findings = @tools.scan(task: task, context: context)
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

        findings.merge("best_practices" => @tools.best_practices)
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
