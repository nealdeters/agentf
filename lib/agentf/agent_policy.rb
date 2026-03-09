# frozen_string_literal: true

module Agentf
  class AgentPolicy
    REQUIRED_KEYS = %w[always ask_first never].freeze

    def validate(agent_name:, boundaries:, context: {}, result: nil, phase: :any)
      errors = []
      boundaries = normalize(boundaries)

      if %i[any before].include?(phase)
        required_inputs = Array(boundaries["required_inputs"])
        missing_inputs = required_inputs.reject { |key| context.key?(key) }
        unless missing_inputs.empty?
          errors << violation(
            code: "missing_required_inputs",
            severity: "error",
            message: "#{agent_name} missing required inputs: #{missing_inputs.join(', ')}",
            agent: agent_name
          )
        end
      end

      if %i[any after].include?(phase)
        required_outputs = Array(boundaries["required_outputs"])
        missing_outputs = required_outputs.reject { |key| output_present?(result, key) }
        unless missing_outputs.empty?
          errors << violation(
            code: "missing_required_outputs",
            severity: "error",
            message: "#{agent_name} missing required outputs: #{missing_outputs.join(', ')}",
            agent: agent_name
          )
        end
      end

      if result.is_a?(Hash) && result["error"]
        errors << violation(
          code: "agent_result_error",
          severity: "warn",
          message: "#{agent_name} returned an error: #{result['error']}",
          agent: agent_name
        )
      end

      errors
    end

    def normalize(boundaries)
      payload = (boundaries || {}).transform_keys(&:to_s)
      REQUIRED_KEYS.each { |key| payload[key] = Array(payload[key]) }
      payload["required_inputs"] = Array(payload["required_inputs"])
      payload["required_outputs"] = Array(payload["required_outputs"])
      payload
    end

    private

    def output_present?(result, key)
      return false unless result.is_a?(Hash)
      return false unless result.key?(key)

      value = result[key]
      !value.nil?
    end

    def violation(code:, severity:, message:, agent:)
      {
        "code" => code,
        "severity" => severity,
        "message" => message,
        "agent" => agent,
        "type" => "agent_policy"
      }
    end
  end
end
