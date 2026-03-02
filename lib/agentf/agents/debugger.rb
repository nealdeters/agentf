# frozen_string_literal: true

require_relative "base"
require_relative "../tools/debugger"

module Agentf
  module Agents
    # Debugger Agent - Error analysis and diagnosis
    class Debugger < Base
      def initialize(memory, tools: nil)
        super(memory)
        @tools = tools || Agentf::Tools::Debugger.new
      end

      def diagnose(error, context: nil)
        log "Diagnosing error"
        log "  Error: #{error[0..100]}..."

        analysis = @tools.parse_error(error)

        memory.store_episode(
          type: "lesson",
          title: "Debugged: #{error[0..50]}...",
          description: "Root cause: #{analysis.possible_causes.first}. Fix: #{analysis.suggested_fix}",
          context: context.to_s,
          tags: ["debugging", "error", "fix"],
          agent: name
        )

        log "Root cause: #{analysis.possible_causes.first}"
        log "Suggested fix: #{analysis.suggested_fix}"

        {
          "error" => error,
          "analysis" => {
            "error_type" => analysis.error_type,
            "possible_causes" => analysis.possible_causes,
            "suggested_fix" => analysis.suggested_fix,
            "stack_trace" => analysis.stack_trace
          }
        }
      end
    end
  end
end
