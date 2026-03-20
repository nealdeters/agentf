# frozen_string_literal: true

require_relative "base"
require_relative "../commands"

module Agentf
  module Agents
    # Designer Agent - Design specs to implementation
    class Designer < Base
      DESCRIPTION = "UI/UX implementation from design specs."
      COMMANDS = %w[generate_component validate_design_system].freeze
      MEMORY_CONCEPTS = {
        "reads" => [],
        "writes" => ["store_episode"],
        "policy" => "Capture successful design implementation patterns."
      }.freeze

      def self.description
        DESCRIPTION
      end

      def self.commands
        COMMANDS
      end

      def self.typed_name
        Agentf::AgentRoles::UI_ENGINEER
      end

      def self.when_to_use
        "Use for transforming design specs into framework-ready UI components."
      end

      def self.deliverables
        ["Component implementation", "Generated UI code", "Design-system alignment"]
      end

      def self.working_style
        "Specification-driven with implementation-grade UI output."
      end

      def self.memory_concepts
        MEMORY_CONCEPTS
      end

      def self.policy_boundaries
        {
          "always" => ["Return generated component details", "Persist successful implementation pattern"],
          "ask_first" => ["Changing primary UI framework", "Persisting successful implementation patterns to memory"],
          "never" => ["Return empty generated code for successful design task"],
          "required_inputs" => ["design_spec"],
          "required_outputs" => ["component", "generated_code", "success"]
        }
      end

      def initialize(memory, commands: nil)
        super(memory)
        @commands = commands || Agentf::Commands::Designer.new
      end

      def implement_design(design_spec, framework: "react")
        execute_with_contract(context: { "design_spec" => design_spec, "framework" => framework }) do
          log "Implementing design: #{design_spec}"

          spec = @commands.generate_component("GeneratedComponent", design_spec)

          res = safe_memory_write(attempted: { action: "store_episode", title: "Implemented design: #{design_spec}", outcome: "positive", agent: name }) do
            memory.store_episode(
              type: "episode",
              title: "Implemented design: #{design_spec}",
              description: "Created #{spec.name} in #{spec.framework}",
              context: "Framework: #{framework}",
              agent: name,
              outcome: "positive"
            )
          end

          if res.is_a?(Hash) && res["confirmation_required"]
            return { "design_spec" => design_spec, "component" => spec.name, "framework" => framework, "generated_code" => spec.code, "success" => true }.merge(res)
          end

          log "Created component: #{spec.name}"

          {
            "design_spec" => design_spec,
            "component" => spec.name,
            "framework" => framework,
            "generated_code" => spec.code,
            "success" => true
          }
        end
      end

      def execute(task:, context: {}, agents: {}, commands: {}, logger: nil)
        spec = task.is_a?(String) ? task : context["design_spec"]
        implement_design(spec, framework: context["framework"] || "react")
      end
    end
  end
end
