# frozen_string_literal: true

require_relative "arg_parser"
require_relative "../commands/registry"
require_relative "../commands"
require_relative "../agents"
require_relative "../memory"

module Agentf
  module CLI
    # CLI entry for running a single agent and returning JSON output.
    class Agent
      include ArgParser

      def initialize
        @memory = Agentf::Memory::RedisMemory.new
      end

      def run(args)
        if args.empty? || args.include?("--help") || args.include?("help")
          show_help
          return
        end

        # Allow callers (like the TypeScript plugin) to append `--json` to
        # request machine-readable output. Strip it here so it's not treated as
        # part of the agent payload.
        args = args.dup
        args.delete("--json")

        agent_name = args.shift
        payload = args.join(" ")

        # Build command registry with default implementations
        registry = Agentf::Commands::Registry.new
        # Register known command providers
        registry.register("explorer", Agentf::Commands::Explorer.new)
        registry.register("tester", Agentf::Commands::Tester.new)
        registry.register("debugger", Agentf::Commands::Debugger.new)
        registry.register("designer", Agentf::Commands::Designer.new)
        registry.register("security", Agentf::Commands::SecurityScanner.new)
        registry.register("architecture", Agentf::Commands::Architecture.new)

        # Load agents (classes already required via lib/agentf)
        agents = {}
        Agentf::Agents.constants.each do |const|
          klass = Agentf::Agents.const_get(const)
          next unless klass.is_a?(Class) && klass < Agentf::Agents::Base
          agents[klass.typed_name] = klass.new(@memory)
        end

        agent = agents[agent_name.upcase]
        unless agent
          $stderr.puts JSON.generate({ ok: false, error: "Agent not found: #{agent_name}" })
          exit 1
        end

        # Parse possible JSON payload
        parsed = nil
        begin
          parsed = JSON.parse(payload) unless payload.strip.empty?
        rescue StandardError
          parsed = payload
        end

        result = agent.execute(task: parsed || payload, context: {}, agents: agents, commands: registry, logger: method(:puts))

        puts JSON.generate(result)
      end

      def show_help
        puts <<~HELP
          Usage: agentf agent <AGENT_NAME> [payload]

          Runs a single agent and prints JSON result.
        HELP
      end
    end
  end
end
