# frozen_string_literal: true

module Agentf
  module Tools
    # Data class for error analysis
    class ErrorAnalysis
      attr_reader :error_type, :message, :location, :possible_causes, :suggested_fix, :stack_trace

      def initialize(error_type:, message:, location:, possible_causes:, suggested_fix:, stack_trace: [])
        @error_type = error_type
        @message = message
        @location = location
        @possible_causes = possible_causes
        @suggested_fix = suggested_fix
        @stack_trace = stack_trace
      end
    end
  end
end
