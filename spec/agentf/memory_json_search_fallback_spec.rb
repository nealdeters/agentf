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
      episode_id = memory.store_episode(type: "test", title: "t", description: "d", agent: Agentf::AgentRoles::ORCHESTRATOR, confirm: true)
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

    it "disables vector search support when episodic index lacks vector fields" , :aggregate_failures do
      client = double("redis-client")
      allow(Redis).to receive(:new).and_return(client)

      allow(client).to receive(:call) do |cmd, *rest|
        case cmd
        when "FT.INFO"
          ["index_name", Agentf::Memory::RedisMemory::EPISODIC_INDEX, "attributes", [["identifier", "$.title", "attribute", "title", "type", "TEXT"]]]
        else
          nil
        end
      end

      memory = described_class.new(project: project)
      expect(memory.instance_variable_get(:@search_supported)).to be true
      expect(memory.instance_variable_get(:@vector_search_supported)).to be false
    end

    it "falls back to non-vector episodic index creation when vector schema is unsupported" , :aggregate_failures do
      client = double("redis-client")
      allow(Redis).to receive(:new).and_return(client)

      create_calls = []
      allow(client).to receive(:call) do |cmd, *rest|
        case cmd
        when "JSON.SET"
          nil
        when "JSON.DEL"
          nil
        when "FT.INFO"
          raise Redis::CommandError.new("Unknown index name")
        when "FT.CREATE"
          create_calls << rest
          raise Redis::CommandError.new("VECTOR is not supported") if rest.include?("VECTOR")

          nil
        when "FT.SEARCH"
          nil
        else
          nil
        end
      end

      memory = described_class.new(project: project)

      episodic_creates = create_calls.select { |args| args.first == Agentf::Memory::RedisMemory::EPISODIC_INDEX }
      expect(episodic_creates.length).to eq(2)
      expect(episodic_creates.first).to include("VECTOR")
      expect(episodic_creates.last).not_to include("VECTOR")
      expect(memory.instance_variable_get(:@vector_search_supported)).to be false
    end
  end
end
