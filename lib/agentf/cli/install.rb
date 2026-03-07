# frozen_string_literal: true

require "pathname"

module Agentf
  module CLI
    # CLI subcommand for generating provider manifests.
    # Wraps the existing Agentf::Installer with CLI argument parsing.
    class Install
      include ArgParser

      def initialize
        @options = {
          providers: ["opencode"],
          scope: "all",
          global_root: Dir.home,
          local_root: Dir.pwd,
          dry_run: false,
          only_agents: nil,
          only_commands: nil
        }
      end

      def run(args)
        parse_args(args)

        if args.include?("help") || args.include?("--help") || args.include?("-h")
          show_help
          return
        end

        installer = Agentf::Installer.new(
          global_root: @options[:global_root],
          local_root: @options[:local_root],
          dry_run: @options[:dry_run]
        )

        results = installer.install(
          providers: @options[:providers],
          scope: @options[:scope],
          only_agents: @options[:only_agents],
          only_commands: @options[:only_commands]
        )

        results.each do |result|
          puts "#{result.fetch("status").upcase}: #{Pathname.new(result.fetch("path")).cleanpath}"
        end

        puts "\nCompleted #{results.size} manifest operations."
      end

      private

      def parse_args(args)
        # Extract --dry-run flag
        @options[:dry_run] = !args.delete("--dry-run").nil?

        # Extract --provider
        provider_val = parse_single_option(args, "--provider=") || parse_single_option(args, "-p=")
        if provider_val
          providers = provider_val.split(",").map { |item| item.strip.downcase }.reject(&:empty?)
          @options[:providers] = providers == ["all"] ? Agentf::Installer::PROVIDER_LAYOUTS.keys : providers
        end

        # Extract --scope
        scope_val = parse_single_option(args, "--scope=") || parse_single_option(args, "-s=")
        @options[:scope] = scope_val.downcase if scope_val

        # Extract --global-root and --local-root
        global_root = parse_single_option(args, "--global-root=")
        @options[:global_root] = File.expand_path(global_root) if global_root

        local_root = parse_single_option(args, "--local-root=")
        @options[:local_root] = File.expand_path(local_root) if local_root

        # Extract --agent and --command filters
        agent_val = parse_single_option(args, "--agent=")
        if agent_val
          @options[:only_agents] = agent_val.split(",").map { |item| item.strip.downcase }.reject(&:empty?)
        end

        command_val = parse_single_option(args, "--command=")
        if command_val
          @options[:only_commands] = command_val.split(",").map { |item| item.strip.downcase }.reject(&:empty?)
        end
      end

      def show_help
        puts <<~HELP
          Usage: agentf install [options]

          Generates provider-specific agent and command manifests.

          Options:
            --provider=LIST        Providers: opencode,copilot,all (default: opencode)
            --scope=SCOPE          Install scope: global|local|all (default: all)
            --global-root=PATH     Root for global installs (default: $HOME)
            --local-root=PATH      Root for local installs (default: current directory)
            --agent=LIST           Only install specific agents (comma-separated)
            --command=LIST         Only install specific commands (comma-separated)
            --dry-run              Show planned writes without writing files

          Examples:
            agentf install
            agentf install --provider=opencode,copilot --scope=local
            agentf install --provider=copilot --dry-run
            agentf install --agent=architect,specialist
        HELP
      end
    end
  end
end
