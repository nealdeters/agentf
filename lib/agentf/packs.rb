# frozen_string_literal: true

module Agentf
  module Packs
    PROFILES = {
      "generic" => {
        "name" => "Generic",
        "description" => "Default provider workflows without domain specialization.",
        "keywords" => [],
        "workflow_templates" => {}
      },
      "rails_standard" => {
        "name" => "Rails Standard",
        "description" => "Thin models/controllers with services, queries, presenters, and policy reviews.",
        "keywords" => %w[rails activerecord rspec pundit viewcomponent hotwire turbo stimulus],
        "workflow_templates" => {
          "feature" => %w[ARCHITECT EXPLORER SPECIALIST TESTER SECURITY REVIEWER DOCUMENTER],
          "bugfix" => %w[ARCHITECT DEBUGGER SPECIALIST TESTER SECURITY REVIEWER],
          "refactor" => %w[ARCHITECT EXPLORER SPECIALIST TESTER REVIEWER],
          "quick_fix" => %w[SPECIALIST TESTER REVIEWER],
          "exploration" => %w[EXPLORER]
        }
      },
      "rails_37signals" => {
        "name" => "Rails 37signals",
        "description" => "Resource-centric workflows favoring concerns, CRUD and model-rich patterns.",
        "keywords" => %w[rails concern crud closure model minitest hotwire],
        "workflow_templates" => {
          "feature" => %w[ARCHITECT EXPLORER SPECIALIST TESTER REVIEWER DOCUMENTER],
          "bugfix" => %w[ARCHITECT DEBUGGER SPECIALIST TESTER REVIEWER],
          "refactor" => %w[ARCHITECT SPECIALIST TESTER REVIEWER],
          "quick_fix" => %w[SPECIALIST REVIEWER],
          "exploration" => %w[EXPLORER]
        }
      },
      "rails_feature_spec" => {
        "name" => "Rails Feature Spec",
        "description" => "Feature-spec-first orchestration with planning and review emphasis.",
        "keywords" => %w[rails feature specification acceptance criteria],
        "workflow_templates" => {
          "feature" => %w[ARCHITECT EXPLORER DESIGNER SPECIALIST TESTER REVIEWER DOCUMENTER],
          "bugfix" => %w[ARCHITECT DEBUGGER SPECIALIST TESTER REVIEWER],
          "refactor" => %w[ARCHITECT EXPLORER SPECIALIST TESTER REVIEWER],
          "quick_fix" => %w[SPECIALIST REVIEWER],
          "exploration" => %w[EXPLORER]
        }
      }
    }.freeze

    module_function

    def all
      PROFILES
    end

    def fetch(name)
      PROFILES[name.to_s.downcase] || PROFILES["generic"]
    end

    def infer(context = {})
      text = [context["task"], context["design_spec"], context["stack"], context["framework"]]
             .compact.join(" ").downcase
      return "generic" if text.empty?

      return "rails_standard" if includes_any_keyword?(text, PROFILES["rails_standard"]["keywords"])

      "generic"
    end

    def includes_any_keyword?(text, keywords)
      keywords.any? { |keyword| text.include?(keyword) }
    end
  end
end
