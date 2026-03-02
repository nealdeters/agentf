# frozen_string_literal: true

require_relative "base"
require_relative "../tools/tester"

module Agentf
  module Agents
    # Tester Agent - Test generation and execution
    class Tester < Base
      def initialize(memory, tools: nil)
        super(memory)
        @tools = tools || Agentf::Tools::Tester.new
      end

      def generate_tests(code_file, test_type: "unit")
        log "Generating #{test_type} tests for: #{code_file}"

        template = @tools.generate_unit_tests(code_file)

        memory.store_success(
          title: "Generated #{test_type} tests for #{code_file}",
          description: "Created #{template.test_file} with #{test_type} tests",
          context: "Test framework: #{template.framework}",
          tags: ["testing", test_type, code_file.split(".").last],
          agent: name
        )

        log "Created: #{template.test_file}"

        {
          "source_file" => code_file,
          "test_file" => template.test_file,
          "test_type" => test_type,
          "generated_code" => template.test_code
        }
      end

      def run_tests(test_file)
        log "Running tests: #{test_file}"

        result = @tools.run_tests(test_file: test_file)

        log "Tests passed: #{result['passed']}"

        { "test_file" => test_file, "passed" => result["passed"] }
      end
    end
  end
end
