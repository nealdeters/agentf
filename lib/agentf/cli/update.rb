# frozen_string_literal: true

require "pathname"
require "fileutils"

module Agentf
  module CLI
    # CLI subcommand for updating provider manifests when the gem version changes.
    #
    # Compares a `.agentf-version` stamp file in each provider directory against
    # `Agentf::VERSION`. If the stamp is missing or outdated, re-runs the
    # installer and writes the new stamp. Skips when already current unless
    # `--force` is given.
    #
    # Usage:
    #   agentf update
    #   agentf update --force
    #   agentf update --provider=opencode,copilot --scope=local
    class Update
      include ArgParser

      # Maps each provider to the directory where its stamp file lives.
      STAMP_DIRS = {
        "opencode" => ".opencode",
        "copilot"  => ".github"
      }.freeze

      STAMP_FILENAME = ".agentf-version"

      def initialize(installer_class: Agentf::Installer)
        @installer_class = installer_class
        @options = {
          providers: ["opencode"],
          scope: "all",
          global_root: Dir.home,
          local_root: Dir.pwd,
          force: false,
          opencode_runtime: "mcp"
        }
      end

      def run(args)
        if args.include?("help") || args.include?("--help") || args.include?("-h")
          show_help
          return
        end

        parse_args(args)

        roots = roots_for(@options[:scope])
        any_updated = false

        @options[:providers].each do |provider|
          roots.each do |root|
            updated = update_provider(provider: provider, root: root)
            any_updated = true if updated
          end
        end

        puts "\nAlready up to date." unless any_updated
      end

      private

      def parse_args(args)
        @options[:force] = !args.delete("--force").nil?

        provider_val = parse_single_option(args, "--provider=") || parse_single_option(args, "-p=")
        if provider_val
          providers = provider_val.split(",").map { |item| item.strip.downcase }.reject(&:empty?)
          @options[:providers] = providers == ["all"] ? Agentf::Installer::PROVIDER_LAYOUTS.keys : providers
        end

        scope_val = parse_single_option(args, "--scope=") || parse_single_option(args, "-s=")
        @options[:scope] = scope_val.downcase if scope_val

        global_root = parse_single_option(args, "--global-root=")
        @options[:global_root] = File.expand_path(global_root) if global_root

        local_root = parse_single_option(args, "--local-root=")
        @options[:local_root] = File.expand_path(local_root) if local_root

        opencode_runtime = parse_single_option(args, "--opencode-runtime=")
        @options[:opencode_runtime] = opencode_runtime if opencode_runtime
      end

      def roots_for(scope)
        case scope
        when "global"
          [@options[:global_root]]
        when "local"
          [@options[:local_root]]
        else
          [@options[:global_root], @options[:local_root]]
        end
      end

      def update_provider(provider:, root:)
        stamp_dir = STAMP_DIRS.fetch(provider) do
          $stderr.puts "Unknown provider: #{provider}"
          return false
        end

        stamp_path = File.join(root, stamp_dir, STAMP_FILENAME)
        installed_version = read_stamp(stamp_path)

        if installed_version == Agentf::VERSION && !@options[:force]
          puts "#{provider} (#{shorten(root)}): up to date (v#{Agentf::VERSION})"
          return false
        end

        migrate_old_files(root, provider) if @options[:force]

        action = installed_version ? "Updating #{installed_version} -> #{Agentf::VERSION}" : "Installing v#{Agentf::VERSION}"
        action = "Force reinstalling v#{Agentf::VERSION}" if @options[:force] && installed_version == Agentf::VERSION
        puts "#{provider} (#{shorten(root)}): #{action}"

        installer = @installer_class.new(
          global_root: root,
          local_root: root,
          opencode_runtime: @options[:opencode_runtime]
        )

        results = installer.install(
          providers: [provider],
          scope: "local"
        )

        results.each do |result|
          puts "  #{result.fetch('status').upcase}: #{Pathname.new(result.fetch('path')).cleanpath}"
        end

        write_stamp(stamp_path, Agentf::VERSION)
        puts "  Stamp: #{Agentf::VERSION} -> #{shorten(stamp_path)}"
        true
      end

      def migrate_old_files(root, provider)
        return unless provider == "opencode"

        opencode_dir = File.join(root, ".opencode")
        return unless Dir.exist?(opencode_dir)

        old_files = [
          File.join(opencode_dir, "tools", "agentf-tools.ts"),
          File.join(opencode_dir, "agents", "ORCHESTRATOR.md"),
          File.join(opencode_dir, "memory", "REDIS_SCHEMA.md")
        ]

        old_agent_names = %w[RESEARCHER PLANNER UI_ENGINEER INCIDENT_RESPONDER REVIEWER QA_TESTER KNOWLEDGE_MANAGER SECURITY_REVIEWER ENGINEER]
        old_files.concat(old_agent_names.map { |name| File.join(opencode_dir, "agents", "#{name}.md") })

        old_command_names = %w[explorer tester metrics security_scanner memory_reviewer designer debugger architecture]
        old_files.concat(old_command_names.map { |name| File.join(opencode_dir, "commands", "#{name}.md") })

        removed_count = 0
        old_files.each do |file|
          next unless File.exist?(file)

          File.delete(file)
          puts "  REMOVED: #{shorten(file)}"
          removed_count += 1
        end

        puts "  Migration: removed #{removed_count} old files" if removed_count > 0
      end

      def read_stamp(path)
        return nil unless File.exist?(path)

        File.read(path).strip
      rescue SystemCallError
        nil
      end

      def write_stamp(path, version)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "#{version}\n")
      end

      def shorten(path)
        home = Dir.home
        path.start_with?(home) ? path.sub(home, "~") : path
      end

      def show_help
        puts <<~HELP
          Usage: agentf update [options]

          Regenerates provider manifests when the agentf gem version changes.
          Compares a .agentf-version stamp file against the current version.
          Skips providers that are already up to date unless --force is used.

          Options:
            --provider=LIST        Providers: opencode,copilot,all (default: opencode)
            --scope=SCOPE          Update scope: global|local|all (default: all)
            --global-root=PATH     Root for global installs (default: $HOME)
            --local-root=PATH      Root for local installs (default: current directory)
            --opencode-runtime=MODE Opencode runtime: mcp|plugin (default: mcp)
            --force                Regenerate even if version matches

          Examples:
            agentf update
            agentf update --force
            agentf update --provider=opencode,copilot --scope=local
            agentf update --provider=opencode --opencode-runtime=plugin
        HELP
      end
    end
  end
end
