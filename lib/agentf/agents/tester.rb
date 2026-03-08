# frozen_string_literal: true

require_relative "base"
require_relative "../commands"

module Agentf
  module Agents
    # Tester Agent - Test generation and execution
    class Tester < Base
      DESCRIPTION = "Automated test generation and execution."
      COMMANDS = %w[detect_framework generate_unit_tests run_tests].freeze
      MEMORY_CONCEPTS = {
        "reads" => [],
        "writes" => ["store_success"],
        "policy" => "Persist test generation outcomes for future reuse."
      }.freeze

      def self.description
        DESCRIPTION
      end

      def self.commands
        COMMANDS
      end

      def self.typed_name
        Agentf::AgentRoles::QA_TESTER
      end

      def self.when_to_use
        "Use for test generation, red/green validation, and execution verification."
      end

      def self.deliverables
        ["Generated test artifacts", "Pass/fail evidence", "TDD phase signals"]
      end

      def self.working_style
        "Quality-gate oriented with explicit pass/fail reporting."
      end

      def self.memory_concepts
        MEMORY_CONCEPTS
      end

      def self.policy_boundaries
        {
          "always" => ["Produce framework-aware tests", "Verify red/green state when TDD enabled"],
          "ask_first" => ["Changing test framework conventions"],
          "never" => ["Mark passing when command output is uncertain"],
          "required_inputs" => [],
          "required_outputs" => ["test_file"]
        }
      end

      def initialize(memory, commands: nil)
        super(memory)
        @commands = commands || Agentf::Commands::Tester.new
      end

      def generate_tests(code_file, test_type: "unit")
        log "Generating #{test_type} tests for: #{code_file}"

        template = @commands.generate_unit_tests(code_file)

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

        result = @commands.run_tests(test_file: test_file)

        log "Tests passed: #{result['passed']}"

        { "test_file" => test_file, "passed" => result["passed"] }
      end
    end
  end
end
