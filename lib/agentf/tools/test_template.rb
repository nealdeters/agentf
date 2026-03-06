# frozen_string_literal: true

module Agentf
  module Commands
    # Data class for test templates
    class TestTemplate
      attr_reader :test_file, :test_code, :framework, :dependencies

      def initialize(test_file:, test_code:, framework:, dependencies: [])
        @test_file = test_file
        @test_code = test_code
        @framework = framework
        @dependencies = dependencies
      end
    end
  end
end
