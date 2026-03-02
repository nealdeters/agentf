# frozen_string_literal: true

require_relative "base"
require_relative "../tools/designer"

module Agentf
  module Agents
    # Designer Agent - Design specs to implementation
    class Designer < Base
      def initialize(memory, tools: nil)
        super(memory)
        @tools = tools || Agentf::Tools::Designer.new
      end

      def implement_design(design_spec, framework: "react")
        log "Implementing design: #{design_spec}"

        spec = @tools.generate_component("GeneratedComponent", design_spec)

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
