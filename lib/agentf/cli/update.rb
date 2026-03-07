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
          force: false
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

        action = installed_version ? "Updating #{installed_version} -> #{Agentf::VERSION}" : "Installing v#{Agentf::VERSION}"
        action = "Force reinstalling v#{Agentf::VERSION}" if @options[:force] && installed_version == Agentf::VERSION
        puts "#{provider} (#{shorten(root)}): #{action}"

        installer = @installer_class.new(
          global_root: root,
          local_root: root
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
            --force                Regenerate even if version matches

          Examples:
            agentf update
            agentf update --force
            agentf update --provider=opencode,copilot --scope=local
        HELP
      end
    end
  end
end
