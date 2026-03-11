# frozen_string_literal: true

require "spec_helper"

RSpec.describe Agentf::Memory::RedisMemory do
  let(:project) { "test-project" }

  it "skips non-hash relationships and empty targets when persisting" do
    client = double("redis-client")
    allow(Redis).to receive(:new).and_return(client)
    allow(client).to receive(:call).and_return(nil)

    memory = described_class.new(project: project)
    allow(memory).to receive(:store_edge)

    relationships = ["not-a-hash", { "to" => "", "type" => "t" }, { "to" => "ok", "type" => "rel" }]

    memory.send(:persist_relationship_edges, episode_id: "eX", related_task_id: nil, relationships: relationships, metadata: {}, tags: [], agent: Agentf::AgentRoles::ORCHESTRATOR)

    # Only the valid hash with non-empty target should have caused a store_edge call
    expect(memory).to have_received(:store_edge).with(hash_including(source_id: "eX", target_id: "ok", relation: "rel")).once
  end

  it "rescues errors from store_edge and returns nil" do
    client = double("redis-client")
    allow(Redis).to receive(:new).and_return(client)
    allow(client).to receive(:call).and_return(nil)

    memory = described_class.new(project: project)
    # make store_edge raise on invocation
    allow(memory).to receive(:store_edge).and_raise(StandardError.new("boom"))

    # Should not raise despite store_edge raising internally
    expect { memory.send(:persist_relationship_edges, episode_id: "eX", related_task_id: "rt", relationships: [{ "to" => "t" }], metadata: {}, tags: [], agent: Agentf::AgentRoles::ORCHESTRATOR) }.not_to raise_error
  end

  it "raises a Redis::CommandError when JSON.SET fails with a non-missing-json-module error during store_episode" do
    client = double("redis-client")
    allow(Redis).to receive(:new).and_return(client)
    # allow normal calls during initialization
    allow(client).to receive(:call).and_return(nil)
    allow(client).to receive(:set).and_return("OK")

    memory = described_class.new(project: project)

    # Force JSON path to be used then simulate an unexpected JSON.SET failure
    memory.instance_variable_set(:@json_supported, true)
    allow(client).to receive(:call).with("JSON.SET", anything, ".", anything).and_raise(Redis::CommandError.new("Permission denied"))

    expect {
      memory.store_episode(type: "x", title: "t", description: "d", tags: [], agent: Agentf::AgentRoles::ORCHESTRATOR, confirm: true)
    }.to raise_error(Redis::CommandError, /Failed to persist episode with RedisJSON/)
  end
end
