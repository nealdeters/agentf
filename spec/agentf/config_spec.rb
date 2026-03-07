# frozen_string_literal: true

RSpec.describe Agentf::Config do
  subject(:config) { Agentf::Config.new }

  describe "#initialize" do
    around do |example|
      original_redis = ENV.delete("REDIS_URL")
      original_project = ENV.delete("AGENTF_PROJECT_NAME")
      original_metrics = ENV.delete("AGENTF_METRICS_ENABLED")
      original_contract_enabled = ENV.delete("AGENTF_WORKFLOW_CONTRACT_ENABLED")
      original_contract_mode = ENV.delete("AGENTF_WORKFLOW_CONTRACT_MODE")
      original_default_pack = ENV.delete("AGENTF_DEFAULT_PACK")

      example.run
    ensure
      original_redis.nil? ? ENV.delete("REDIS_URL") : ENV["REDIS_URL"] = original_redis
      original_project.nil? ? ENV.delete("AGENTF_PROJECT_NAME") : ENV["AGENTF_PROJECT_NAME"] = original_project
      original_metrics.nil? ? ENV.delete("AGENTF_METRICS_ENABLED") : ENV["AGENTF_METRICS_ENABLED"] = original_metrics
      original_contract_enabled.nil? ? ENV.delete("AGENTF_WORKFLOW_CONTRACT_ENABLED") : ENV["AGENTF_WORKFLOW_CONTRACT_ENABLED"] = original_contract_enabled
      original_contract_mode.nil? ? ENV.delete("AGENTF_WORKFLOW_CONTRACT_MODE") : ENV["AGENTF_WORKFLOW_CONTRACT_MODE"] = original_contract_mode
      original_default_pack.nil? ? ENV.delete("AGENTF_DEFAULT_PACK") : ENV["AGENTF_DEFAULT_PACK"] = original_default_pack
    end

    it "uses default Redis URL from env" do
      expect(config.redis_url).to eq("redis://localhost:6379")
    end

    it "uses default project name from env" do
      expect(config.project_name).to eq("default")
    end

    it "enables metrics by default" do
      expect(config.metrics_enabled).to be true
    end

    it "enables workflow contract by default" do
      expect(config.workflow_contract_enabled).to be true
      expect(config.workflow_contract_mode).to eq("advisory")
    end

    it "uses generic pack by default" do
      expect(config.default_pack).to eq("generic")
    end

    it "disables metrics when env flag is false" do
      ENV["AGENTF_METRICS_ENABLED"] = "false"
      flagged_config = Agentf::Config.new
      expect(flagged_config.metrics_enabled).to be false
    end

    it "supports contract env flags" do
      ENV["AGENTF_WORKFLOW_CONTRACT_ENABLED"] = "false"
      ENV["AGENTF_WORKFLOW_CONTRACT_MODE"] = "enforcing"
      flagged_config = Agentf::Config.new
      expect(flagged_config.workflow_contract_enabled).to be false
      expect(flagged_config.workflow_contract_mode).to eq("enforcing")
    end
  end

  describe "attributes" do
    it "allows setting redis_url" do
      config.redis_url = "redis://custom:6379"
      expect(config.redis_url).to eq("redis://custom:6379")
    end

    it "allows setting project_name" do
      config.project_name = "my-project"
      expect(config.project_name).to eq("my-project")
    end

    it "allows setting base_path" do
      config.base_path = "/custom/path"
      expect(config.base_path).to eq("/custom/path")
    end

    it "allows setting metrics_enabled" do
      config.metrics_enabled = false
      expect(config.metrics_enabled).to be false
    end

    it "allows setting workflow contract and pack fields" do
      config.workflow_contract_enabled = false
      config.workflow_contract_mode = "off"
      config.default_pack = "rails_standard"
      expect(config.workflow_contract_enabled).to be false
      expect(config.workflow_contract_mode).to eq("off")
      expect(config.default_pack).to eq("rails_standard")
    end
  end
end

RSpec.describe Agentf do
  describe ".config" do
    it "returns a Config instance" do
      expect(Agentf.config).to be_a(Agentf::Config)
    end

    it "memoizes the config" do
      expect(Agentf.config).to equal(Agentf.config)
    end
  end

  describe ".configure" do
    it "yields the config block" do
      original_url = Agentf.config.redis_url
      Agentf.configure do |c|
        c.redis_url = "redis://test:6379"
      end

      expect(Agentf.config.redis_url).to eq("redis://test:6379")

      # Restore to avoid polluting other tests
      Agentf.config.redis_url = original_url
    end

    it "does not yield if no block given" do
      expect { Agentf.configure }.not_to raise_error
    end
  end

  describe "Error class" do
    it "is a StandardError" do
      expect(Agentf::Error < StandardError).to be true
    end

    it "can be raised with message" do
      expect { raise Agentf::Error, "test error" }.to raise_error(Agentf::Error, "test error")
    end
  end
end
