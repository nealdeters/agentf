# frozen_string_literal: true

require "json"
require "yaml"

module Agentf
  module Evals
    class Scenario
      DEFAULT_TIMEOUT_SECONDS = 30

      attr_reader :path, :metadata

      def self.discover(root)
        return [] unless Dir.exist?(root)

        Dir.children(root).sort.filter_map do |entry|
          scenario_dir = File.join(root, entry)
          next unless File.directory?(scenario_dir)

          load(scenario_dir)
        rescue StandardError
          nil
        end
      end

      def self.load(path)
        metadata_path = File.join(path, "scenario.yml")
        metadata = File.exist?(metadata_path) ? (YAML.load_file(metadata_path) || {}) : {}
        new(path: path, metadata: metadata)
      end

      def initialize(path:, metadata: {})
        @path = path
        @metadata = metadata.transform_keys(&:to_s)
      end

      def name
        metadata.fetch("name", File.basename(path))
      end

      def description
        metadata.fetch("description", "")
      end

      def execution_mode
        metadata.fetch("execution_mode", "agent").to_s
      end

      def agent
        metadata["agent"]
      end

      def mcp_tool
        metadata["mcp_tool"]
      end

      def provider_name
        metadata["provider"]
      end

      def provider_runtime_tool
        metadata["provider_runtime_tool"]
      end

      def provider_scope
        metadata.fetch("provider_scope", "local").to_s
      end

      def provider_install_deps?
        return false unless metadata.key?("provider_install_deps")

        metadata["provider_install_deps"] == true
      end

      def install_agents
        Array(metadata["install_agents"]).map(&:to_s)
      end

      def install_commands
        Array(metadata["install_commands"]).map(&:to_s)
      end

      def expected_memory_titles
        Array(metadata["expected_memory_titles"]).map(&:to_s)
      end

      def prompt
        File.read(prompt_path)
      end

      def prompt_payload
        content = prompt.to_s
        return content unless json_prompt?

        JSON.parse(content)
      rescue JSON::ParserError
        content
      end

      def json_prompt?
        metadata["prompt_format"].to_s == "json"
      end

      def prompt_path
        File.join(path, "prompt.txt")
      end

      def setup_script_path
        file = File.join(path, "setup.sh")
        File.exist?(file) ? file : nil
      end

      def verify_script_path
        file = File.join(path, "verify.sh")
        File.exist?(file) ? file : nil
      end

      def workspace_path
        file = File.join(path, "workspace")
        Dir.exist?(file) ? file : nil
      end

      def timeout_seconds
        Integer(metadata.fetch("timeout_seconds", DEFAULT_TIMEOUT_SECONDS))
      rescue ArgumentError, TypeError
        DEFAULT_TIMEOUT_SECONDS
      end

      def auto_confirm_memories?
        return true unless metadata.key?("auto_confirm_memories")

        metadata["auto_confirm_memories"] == true
      end

      def env
        raw = metadata.fetch("env", {})
        return {} unless raw.is_a?(Hash)

        raw.transform_keys(&:to_s).transform_values(&:to_s)
      end

      def tags
        Array(metadata["tags"]).map(&:to_s)
      end

      def retry_on_confirmation?
        metadata["retry_on_confirmation"] == true
      end

      def confirmed_write_token
        metadata.fetch("confirmed_write_token", "confirmed")
      end

      def providers
        Array(metadata["providers"]).map(&:to_s)
      end

      def models
        Array(metadata["models"]).map(&:to_s)
      end

      def validate!
        raise ArgumentError, "Scenario missing prompt.txt: #{prompt_path}" unless File.exist?(prompt_path)
        case execution_mode
        when "agent"
          raise ArgumentError, "Scenario missing agent in scenario.yml: #{path}" if agent.to_s.strip.empty?
        when "mcp"
          raise ArgumentError, "Scenario missing mcp_tool in scenario.yml: #{path}" if mcp_tool.to_s.strip.empty?
        when "provider", "provider_runtime"
          raise ArgumentError, "Scenario missing provider in scenario.yml: #{path}" if provider_name.to_s.strip.empty?
          if execution_mode == "provider_runtime" && provider_runtime_tool.to_s.strip.empty?
            raise ArgumentError, "Scenario missing provider_runtime_tool in scenario.yml: #{path}"
          end
        else
          raise ArgumentError, "Unknown execution_mode '#{execution_mode}' for #{path}"
        end
        raise ArgumentError, "Scenario missing verify.sh: #{path}" unless verify_script_path
      end

      def to_h
        {
          "name" => name,
          "description" => description,
          "execution_mode" => execution_mode,
          "agent" => agent,
          "mcp_tool" => mcp_tool,
          "provider" => provider_name,
          "provider_runtime_tool" => provider_runtime_tool,
          "provider_scope" => provider_scope,
          "provider_install_deps" => provider_install_deps?,
          "install_agents" => install_agents,
          "install_commands" => install_commands,
          "expected_memory_titles" => expected_memory_titles,
          "path" => path,
          "prompt_path" => prompt_path,
          "setup_script_path" => setup_script_path,
          "verify_script_path" => verify_script_path,
          "workspace_path" => workspace_path,
          "timeout_seconds" => timeout_seconds,
          "auto_confirm_memories" => auto_confirm_memories?,
          "retry_on_confirmation" => retry_on_confirmation?,
          "confirmed_write_token" => confirmed_write_token,
          "env" => env,
          "tags" => tags,
          "providers" => providers,
          "models" => models
        }
      end
    end
  end
end
