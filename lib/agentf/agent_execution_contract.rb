# frozen_string_literal: true

module Agentf
  class AgentContractViolation < Agentf::Error
    attr_reader :agent_name, :violations

    def initialize(agent_name:, violations:)
      @agent_name = agent_name
      @violations = violations
      super("Agent contract violated for #{agent_name}: #{violations.map { |v| v['code'] }.join(', ')}")
    end
  end

  class AgentExecutionContract
    def initialize(enabled:, mode:, policy: Agentf::AgentPolicy.new)
      @enabled = enabled
      @mode = normalize_mode(mode)
      @policy = policy
    end

    def enabled?
      @enabled && @mode != "off"
    end

    def enforcing?
      enabled? && @mode == "enforcing"
    end

    def before!(agent_name:, boundaries:, context: {})
      violations = @policy.validate(
        agent_name: agent_name,
        boundaries: boundaries,
        context: context,
        result: nil,
        phase: :before
      )
      handle!(agent_name: agent_name, violations: violations)
    end

    def after!(agent_name:, boundaries:, context: {}, result:)
      violations = @policy.validate(
        agent_name: agent_name,
        boundaries: boundaries,
        context: context,
        result: result,
        phase: :after
      ) + coding_execution_violations(agent_name: agent_name, result: result) + tdd_violations(agent_name: agent_name, context: context)
      handle!(agent_name: agent_name, violations: violations)
    end

    private

    def normalize_mode(value)
      mode = value.to_s.strip.downcase
      return mode if %w[advisory enforcing off].include?(mode)

      "enforcing"
    end

    def handle!(agent_name:, violations:)
      return if violations.empty? || !enabled?

      raise Agentf::AgentContractViolation.new(agent_name: agent_name, violations: violations) if enforcing?
    end

    def tdd_violations(agent_name:, context:)
      return [] unless [Agentf::AgentRoles::ENGINEER, Agentf::AgentRoles::UI_ENGINEER].include?(agent_name)

      tdd_required = context["tdd_required"] == true || context.key?("tdd_phase")
      return [] unless tdd_required

      phase = context["tdd_phase"].to_s.strip
      violations = []
      if phase.empty?
        violations << {
          "code" => "missing_tdd_phase",
          "severity" => "error",
          "message" => "#{agent_name} requires explicit tdd_phase when TDD is enabled",
          "agent" => agent_name,
          "type" => "agent_contract"
        }
      end

      if phase == "green" && context["expected_test_fix"].to_s.strip.empty?
        violations << {
          "code" => "missing_expected_test_fix",
          "severity" => "error",
          "message" => "#{agent_name} green phase requires expected_test_fix from failing test",
          "agent" => agent_name,
          "type" => "agent_contract"
        }
      end

      violations
    end

    def coding_execution_violations(agent_name:, result:)
      coding_agents = [Agentf::AgentRoles::ENGINEER, Agentf::AgentRoles::UI_ENGINEER, Agentf::AgentRoles::INCIDENT_RESPONDER]
      return [] unless coding_agents.include?(agent_name)

      unless result.is_a?(Hash) && [true, false].include?(result["success"])
        return [
          {
            "code" => "invalid_success_flag",
            "severity" => "error",
            "message" => "#{agent_name} must return boolean success",
            "agent" => agent_name,
            "type" => "agent_contract"
          }
        ]
      end

      []
    end
  end
end
