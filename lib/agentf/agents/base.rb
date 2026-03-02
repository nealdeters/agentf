# frozen_string_literal: true

module Agentf
  module Agents
    # Base agent class
    class Base
      attr_reader :memory, :name

      def initialize(memory)
        @memory = memory
        @name = self.class.name.split("::").last.upcase
      end

      def log(message)
        puts "\n[#{@name}] #{message}"
      end
    end
  end
end
