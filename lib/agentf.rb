# frozen_string_literal: true

require "dotenv/load"
require "json"
require "time"
require "securerandom"
require "pathname"
require_relative "agentf/version"

module Agentf
  class Error < StandardError; end

  # Global configuration
  class Config
    attr_reader :redis_url
    attr_accessor :project_name, :base_path, :metrics_enabled, :workflow_contract_enabled,
                  :workflow_contract_mode, :default_pack

    def initialize
      @redis_url = normalize_redis_url(ENV.fetch("REDIS_URL", "redis://localhost:6379"))
      @project_name = ENV.fetch("AGENTF_PROJECT_NAME", "default")
      @base_path = Dir.pwd
      @metrics_enabled = parse_boolean(ENV.fetch("AGENTF_METRICS_ENABLED", "true"), default: true)
      @workflow_contract_enabled = parse_boolean(
        ENV.fetch("AGENTF_WORKFLOW_CONTRACT_ENABLED", "true"),
        default: true
      )
      @workflow_contract_mode = normalize_contract_mode(
        ENV.fetch("AGENTF_WORKFLOW_CONTRACT_MODE", "advisory")
      )
      @default_pack = ENV.fetch("AGENTF_DEFAULT_PACK", "generic").to_s.strip.downcase
    end

    def redis_url=(value)
      @redis_url = normalize_redis_url(value)
    end

    private

    def normalize_redis_url(value)
      url = value.to_s.strip
      return "redis://localhost:6379" if url.empty?

      return url if url.match?(/\A[a-z][a-z0-9+\-.]*:\/\//i)

      "redis://#{url}"
    end

    def parse_boolean(value, default:)
      normalized = value.to_s.strip.downcase
      return true if %w[1 true yes on].include?(normalized)
      return false if %w[0 false no off].include?(normalized)

      default
    end

    def normalize_contract_mode(value)
      mode = value.to_s.strip.downcase
      return mode if %w[advisory enforcing off].include?(mode)

      "advisory"
    end
  end

  def self.config
    @config ||= Config.new
  end

  def self.configure
    yield(config) if block_given?
  end
end

# Load submodules
require_relative "agentf/memory"
require_relative "agentf/tools"
require_relative "agentf/commands"
require_relative "agentf/service/providers"
require_relative "agentf/context_builder"
require_relative "agentf/packs"
require_relative "agentf/agent_policy"
require_relative "agentf/workflow_contract"
require_relative "agentf/workflow_engine"
require_relative "agentf/installer"
require_relative "agentf/agents"
require_relative "agentf/cli/router"
