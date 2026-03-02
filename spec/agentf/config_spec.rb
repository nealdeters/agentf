# frozen_string_literal: true

RSpec.describe Agentf::Config do
  subject(:config) { Agentf::Config.new }

  describe "#initialize" do
    around do |example|
      original_redis = ENV.delete("REDIS_URL")
      original_project = ENV.delete("AGENTF_PROJECT_NAME")

      example.run
    ensure
      original_redis.nil? ? ENV.delete("REDIS_URL") : ENV["REDIS_URL"] = original_redis
      original_project.nil? ? ENV.delete("AGENTF_PROJECT_NAME") : ENV["AGENTF_PROJECT_NAME"] = original_project
    end

    it "uses default Redis URL from env" do
      expect(config.redis_url).to eq("redis://localhost:6379")
    end

    it "uses default project name from env" do
      expect(config.project_name).to eq("default")
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
      Agentf.configure do |c|
        c.redis_url = "redis://test:6379"
      end

      expect(Agentf.config.redis_url).to eq("redis://test:6379")
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
