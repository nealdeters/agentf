# frozen_string_literal: true

module Agentf
  module Agents
    # Base agent class
    class Base
      attr_reader :memory, :name

      def self.typed_name
        name.split("::").last.upcase
      end

      def self.description
        "Agent for #{typed_name.downcase}"
      end

      def self.when_to_use
        "Use when the workflow needs #{typed_name.downcase.tr('_', ' ')} expertise."
      end

      def self.deliverables
        []
      end

      def self.working_style
        "Structured, evidence-based, and outcome-oriented."
      end

      def self.commands
        []
      end

      def self.memory_concepts
        {
          "reads" => ["RedisMemory#get_recent_memories", "RedisMemory#get_pitfalls"],
          "writes" => ["RedisMemory#store_lesson", "RedisMemory#store_success", "RedisMemory#store_pitfall"],
          "policy" => "Memory is runtime state in Redis and should not be embedded as raw data in manifest markdown."
        }
      end

      def self.prompt
        "You are the #{typed_name} agent."
      end

      def self.policy_boundaries
        {
          "always" => [],
          "ask_first" => [],
          "never" => [],
          "required_inputs" => [],
          "required_outputs" => []
        }
      end

      def initialize(memory)
        @memory = memory
        @name = self.class.typed_name
        @execution_contract = Agentf::AgentExecutionContract.new(
          enabled: Agentf.config.agent_contract_enabled,
          mode: Agentf.config.agent_contract_mode
        )
      end

      def log(message)
        puts "\n[#{@name}] #{message}"
      end

      private

      def execute_with_contract(context: {})
        @execution_contract.before!(
          agent_name: name,
          boundaries: self.class.policy_boundaries,
          context: context
        )

        result = yield

        @execution_contract.after!(
          agent_name: name,
          boundaries: self.class.policy_boundaries,
          context: context,
          result: result
        )

        result
      end
    end
  end
end
