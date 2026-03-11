# frozen_string_literal: true

require_relative "arg_parser"
require_relative "memory"
require_relative "code"
require_relative "install"
require_relative "update"
require_relative "metrics"
require_relative "architecture"

module Agentf
  module CLI
    # Top-level subcommand router for the unified `agentf` CLI.
    #
    # Usage:
    #   agentf memory recent -n 5
    #   agentf code glob "**/*.rb"
    #   agentf install --provider opencode,copilot
    #   agentf version
    #   agentf help
    class Router
      SUBCOMMANDS = %w[memory code metrics architecture install update mcp-server version help].freeze

      def run(args)
        subcommand = args.shift || "help"

        case subcommand
        when "memory"
          Memory.new.run(args)
        when "code"
          Code.new.run(args)
        when "install"
          Install.new.run(args)
        when "metrics"
          if Agentf.config.metrics_enabled
            Metrics.new.run(args)
          else
            $stderr.puts "Metrics are disabled. Set AGENTF_METRICS_ENABLED=true to enable."
            exit 1
          end
        when "architecture"
          Architecture.new.run(args)
        when "update"
          Update.new.run(args)
        when "mcp-server"
          start_mcp_server
        when "version", "--version", "-v"
          puts "agentf #{Agentf::VERSION}"
        when "help", "--help", "-h"
          show_help
        else
          $stderr.puts "Unknown command: #{subcommand}"
          $stderr.puts
          show_help
          exit 1
        end
      end

      private

      def start_mcp_server
        require_relative "../mcp/server"
        Agentf::MCP::Server.new.run
      end

      def show_help
        puts <<~HELP
          Usage: agentf <command> [subcommand] [options]

          Commands:
            memory       Manage agent memory (lessons, pitfalls, successes, intents)
            code         Explore codebase (glob, grep, tree, related files)
            metrics      Show workflow success and provider parity metrics
            architecture Analyze architecture layers and violations
            install      Generate provider manifests (agents, commands, tools)
            update       Regenerate manifests when gem version changes
            mcp-server   Start MCP server over stdio (for Copilot integration)
            version      Show version

          Global Options:
            --json       Output in JSON format (supported by memory and code)
            --help       Show help for any command

          Env:
            AGENTF_METRICS_ENABLED=true|false   Enable/disable workflow metrics capture and CLI
            AGENTF_WORKFLOW_CONTRACT_ENABLED=true|false   Enable/disable workflow contract checks
            AGENTF_WORKFLOW_CONTRACT_MODE=advisory|enforcing|off   Contract behavior mode
            AGENTF_AGENT_CONTRACT_ENABLED=true|false   Enable/disable per-agent contract checks
            AGENTF_AGENT_CONTRACT_MODE=advisory|enforcing|off   Per-agent contract behavior mode
  (AGENTF_DEFAULT_PACK no longer used — orchestrator uses internal profiles)
            AGENTF_GEM_PATH=/path/to/gem   Path to agentf gem (for OpenCode plugin binary resolution)

          Examples:
            agentf memory recent -n 5
            agentf memory add-lesson "Title" "Description" --agent=PLANNER
            agentf code glob "lib/**/*.rb"
            agentf code grep "def execute" --file-pattern=*.rb
            agentf install --provider opencode,copilot --scope local
            agentf metrics summary -n 100
            agentf metrics parity --json
            agentf architecture analyze
            agentf architecture review --json
            agentf update
            agentf update --force --provider=opencode,copilot
            agentf mcp-server
            agentf version

          Run 'agentf <command> help' for detailed help on a command.
        HELP
      end
    end
  end
end
