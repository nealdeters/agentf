# frozen_string_literal: true

module Agentf
  module Tools
    # Performs lightweight security scanning for workflows
    class SecurityScanner
      DEFAULT_PATTERNS = {
        "AWS Access Key" => /AKIA[0-9A-Z]{16}/,
        "Generic API Key" => /(api|secret|token)_?(key|token)?\s*[:=]\s*[A-Za-z0-9_-]{16,}/i,
        "Private Key" => /-----BEGIN (?:RSA|DSA|EC|OPENSSH) PRIVATE KEY-----/,
        "Password Assignment" => /password\s*[:=]\s*['\"][^'\"]+['\"]/i
      }.freeze

      PROMPT_INJECTION_PATTERNS = [
        /print\s+(?:all\s+)?env/i,
        /show\s+(?:me\s+)?(?:your|the)\s+environment/i,
        /exfiltrate/i,
        /ignore\s+previous\s+instructions/i
      ].freeze

      BEST_PRACTICES = [
        "Use secret scanning tools such as Gitleaks or TruffleHog before committing.",
        "Enable GitHub Secret Scanning Push Protection to block accidental leaks.",
        "Strip sensitive headers/body content from agent logs before persisting.",
        "Sandbox agent file-system access and avoid storing raw secrets in episodic memory.",
        "Harden prompts against injection by refusing to reveal environment variables or credentials."
      ].freeze

      def initialize(patterns: DEFAULT_PATTERNS)
        @patterns = patterns
      end

      def scan(task:, context: {})
        aggregated_text = ([task] + flatten_context(context)).compact.join("\n")

        issues = detect_secret_patterns(aggregated_text) + detect_prompt_injection(aggregated_text)

        {
          "issues" => issues,
          "score" => issues.size,
          "recommendations" => issues.empty? ? [] : BEST_PRACTICES
        }
      end

      def best_practices
        BEST_PRACTICES
      end

      private

      def flatten_context(context)
        case context
        when Hash
          context.flat_map { |k, v| [k.to_s, *flatten_context(v)] }
        when Array
          context.flat_map { |v| flatten_context(v) }
        else
          [context.to_s]
        end
      end

      def detect_secret_patterns(text)
        @patterns.each_with_object([]) do |(label, regex), findings|
          next unless text.match?(regex)

          findings << {
            "issue" => "Potential Secret: #{label}",
            "detail" => "Input matched sensitive pattern #{regex.source}."
          }
        end
      end

      def detect_prompt_injection(text)
        PROMPT_INJECTION_PATTERNS.each_with_object([]) do |regex, findings|
          next unless text.match?(regex)

          findings << {
            "issue" => "Possible Prompt Injection",
            "detail" => "Detected instruction matching #{regex.source}"
          }
        end
      end
    end
  end
end
