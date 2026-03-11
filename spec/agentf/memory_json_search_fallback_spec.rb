# frozen_string_literal: true

require "spec_helper"

RSpec.describe Agentf::Memory::RedisMemory do
  let(:project) { "test-project" }

  context "Redis module detection and fallbacks" do
    it "detects JSON and Search support when commands succeed"  , :aggregate_failures do
      client = double("redis-client")
      allow(Redis).to receive(:new).and_return(client)
      allow(client).to receive(:call).and_return(nil)

      memory = described_class.new(project: project)

      expect(memory.instance_variable_get(:@json_supported)).to be true
      expect(memory.instance_variable_get(:@search_supported)).to be true
    end

    it "falls back to plain SET when RedisJSON is missing and persists episode" do
      client = double("redis-client")
      allow(Redis).to receive(:new).and_return(client)

      allow(client).to receive(:call) do |cmd, *rest|
        case cmd
        when "JSON.SET"
          raise Redis::CommandError.new("Unknown command 'JSON.SET'")
        else
          # FT.INFO and FT.CREATE calls succeed (no exception)
          nil
        end
      end

      allow(client).to receive(:set).and_return("OK")

      memory = described_class.new(project: project)

      # JSON support should have been disabled during initialization
      expect(memory.instance_variable_get(:@json_supported)).to be false

      # Storing an episode should use client.set as a fallback
      expect(client).to receive(:set).at_least(:once)
      episode_id = memory.store_episode(type: "test", title: "t", description: "d", tags: [], agent: Agentf::AgentRoles::ORCHESTRATOR, confirm: true)
      expect(episode_id).to match(/^episode_/)
    end

    it "disables search support when RediSearch is missing" do
      client = double("redis-client")
      allow(Redis).to receive(:new).and_return(client)

      allow(client).to receive(:call) do |cmd, *rest|
        case cmd
        when "FT.INFO"
          raise Redis::CommandError.new("Unknown command 'FT.INFO'")
        else
          nil
        end
      end

      memory = described_class.new(project: project)
      expect(memory.instance_variable_get(:@search_supported)).to be false
    end
  end
end
