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
        "writes" => ["store_success"],
        "policy" => "Capture successful design implementation patterns."
      }.freeze

      def self.description
        DESCRIPTION
      end

      def self.commands
        COMMANDS
      end

      def self.memory_concepts
        MEMORY_CONCEPTS
      end

      def initialize(memory, commands: nil)
        super(memory)
        @commands = commands || Agentf::Commands::Designer.new
      end

      def implement_design(design_spec, framework: "react")
        log "Implementing design: #{design_spec}"

        spec = @commands.generate_component("GeneratedComponent", design_spec)

        memory.store_success(
          title: "Implemented design: #{design_spec}",
          description: "Created #{spec.name} in #{spec.framework}",
          context: "Framework: #{framework}",
          tags: ["design", "ui", framework],
          agent: name
        )

        log "Created component: #{spec.name}"

        {
          "design_spec" => design_spec,
          "component" => spec.name,
          "framework" => framework,
          "generated_code" => spec.code
        }
      end
    end
  end
end
