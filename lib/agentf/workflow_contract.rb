# frozen_string_literal: true

module Agentf
  class WorkflowContract
    STAGES = %w[spec plan execute review finalize].freeze

    def initialize(enabled:, mode:)
      @enabled = enabled
      @mode = normalize_mode(mode)
    end

    def enabled?
      @enabled && @mode != "off"
    end

    def mode
      @mode
    end

    def enforcing?
      enabled? && @mode == "enforcing"
    end

    def check(stage:, workflow_state:, plan: nil)
      return pass(stage) unless enabled?

      violations = case stage
                   when "spec" then check_spec(workflow_state)
                   when "plan" then check_plan(plan)
                   when "execute" then check_execute(workflow_state)
                   when "review" then check_review(workflow_state)
                   when "finalize" then check_finalize(workflow_state)
                   else []
                   end

      {
        "stage" => stage,
        "mode" => @mode,
        "ok" => violations.empty?,
        "blocked" => enforcing? && violations.any?,
        "violations" => violations
      }
    end

    private

    def normalize_mode(value)
      mode = value.to_s.strip.downcase
      return mode if %w[advisory enforcing off].include?(mode)

      "advisory"
    end

    def pass(stage)
      {
        "stage" => stage,
        "mode" => @mode,
        "ok" => true,
        "blocked" => false,
        "violations" => []
      }
    end

    def check_spec(workflow_state)
      context = workflow_state["context"] || {}
      violations = []

      if context["design_spec"].to_s.strip.empty? && context["error"].to_s.strip.empty?
        violations << violation(
          stage: "spec",
          code: "missing_spec_context",
          severity: "warn",
          message: "Expected design_spec or error context before planning"
        )
      end

      violations
    end

    def check_plan(plan)
      violations = []
      agents = Array(plan && plan["agents_needed"])
      if agents.empty?
        violations << violation(
          stage: "plan",
          code: "missing_agent_plan",
          severity: "error",
          message: "Provider plan did not include any agents"
        )
      end
      violations
    end

    def check_execute(workflow_state)
      violations = []
      tdd = workflow_state["tdd"] || {}

      if tdd["enabled"] && !tdd["red_executed"]
        violations << violation(
          stage: "execute",
          code: "tdd_red_not_executed",
          severity: "error",
          message: "TDD red phase must execute before implementation"
        )
      end

      if tdd["enabled"] && tdd["phase"] == "green" && !tdd["green_executed"]
        violations << violation(
          stage: "execute",
          code: "tdd_green_not_verified",
          severity: "warn",
          message: "TDD green verification has not completed"
        )
      end

      violations
    end

    def check_review(workflow_state)
      reviewer_result = Array(workflow_state["results"]).find { |item| item["agent"] == "REVIEWER" }
      return [violation(stage: "review", code: "missing_reviewer", severity: "warn", message: "Reviewer step missing")] unless reviewer_result

      return [] if [true, false].include?(reviewer_result.dig("result", "approved"))

      [
        violation(
          stage: "review",
          code: "invalid_reviewer_result",
          severity: "warn",
          message: "Reviewer result did not contain approved boolean"
        )
      ]
    end

    def check_finalize(workflow_state)
      errors = Array(workflow_state["results"]).count { |item| item.dig("result", "error") }
      return [] if errors.zero?

      [
        violation(
          stage: "finalize",
          code: "workflow_errors_present",
          severity: "error",
          message: "Workflow has #{errors} error result(s)"
        )
      ]
    end

    def violation(stage:, code:, severity:, message:)
      {
        "stage" => stage,
        "code" => code,
        "severity" => severity,
        "message" => message
      }
    end
  end
end
