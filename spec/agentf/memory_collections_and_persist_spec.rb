# frozen_string_literal: true

require "spec_helper"

RSpec.describe Agentf::Memory::RedisMemory do
  let(:project) { "test-project" }

  it "persists relationship edges for related_task_id, relationships, parent and causal_from"  , :aggregate_failures do
    client = double("redis-client")
    allow(Redis).to receive(:new).and_return(client)
    allow(client).to receive(:call).and_return(nil)
    allow(client).to receive(:call).and_return(nil)

    memory = described_class.new(project: project)
    allow(memory).to receive(:store_edge)

    metadata = { "parent_episode_id" => "p1", "causal_from" => "c1", "intent_kind" => "business" }
    relationships = [{ "to" => "t1", "type" => "reltype", "weight" => 2 }, { to: "t2" }]

    memory.send(:persist_relationship_edges, episode_id: "e1", related_task_id: "rt1", relationships: relationships, metadata: metadata, tags: ["a"], agent: Agentf::AgentRoles::ORCHESTRATOR)

    expect(memory).to have_received(:store_edge).with(source_id: "e1", target_id: "rt1", relation: "relates_to", tags: ["a"], agent: Agentf::AgentRoles::ORCHESTRATOR).once
    expect(memory).to have_received(:store_edge).with(hash_including(source_id: "e1", target_id: "t1", relation: "reltype")).once
    expect(memory).to have_received(:store_edge).with(hash_including(source_id: "e1", target_id: "p1", relation: "child_of")).once
    expect(memory).to have_received(:store_edge).with(hash_including(source_id: "e1", target_id: "c1", relation: "caused_by")).once
  end

  it "collects episode records and respects scope/type/agent filters"  , :aggregate_failures do
    client = double("redis-client")
    allow(Redis).to receive(:new).and_return(client)
    # Default allow any call during initialization to succeed
    allow(client).to receive(:call).and_return(nil)
    # scan will be called once returning two episodic keys
    allow(client).to receive(:scan).and_return(["0", ["episodic:1", "episodic:2"]])

    memory = described_class.new(project: project)

    allow(memory).to receive(:load_episode).with("episodic:1").and_return({ "id" => "1", "project" => project, "type" => "t1", "agent" => "A" })
    allow(memory).to receive(:load_episode).with("episodic:2").and_return({ "id" => "2", "project" => "other", "type" => "t1", "agent" => "A" })

    records = memory.send(:collect_episode_records, scope: "project", type: nil, agent: nil)
    expect(records.map { |r| r["id"] }).to include("1")
    expect(records.map { |r| r["id"] }).not_to include("2")

    # Filter by type
    recs_by_type = memory.send(:collect_episode_records, scope: "project", type: "t1", agent: "A")
    expect(recs_by_type.first["id"]).to eq("1")
  end

  it "collects related edge keys by matching source/target ids and respects scope"  , :aggregate_failures do
    client = double("redis-client")
    allow(Redis).to receive(:new).and_return(client)
    allow(client).to receive(:call).and_return(nil)
    allow(client).to receive(:scan).and_return(["0", ["edge:1", "edge:2"]])

    memory = described_class.new(project: project)
    # edge:1 links n1->n2 in project, edge:2 is other project
    allow(memory).to receive(:load_episode).with("edge:1").and_return({ "id" => "edge_1", "source_id" => "n1", "target_id" => "n2", "project" => project })
    allow(memory).to receive(:load_episode).with("edge:2").and_return({ "id" => "edge_2", "source_id" => "x", "target_id" => "y", "project" => "other" })

    keys = memory.send(:collect_related_edge_keys, episode_ids: ["n1"], scope: "project")
    expect(keys).to include("edge:1")
    expect(keys).not_to include("edge:2")
  end

  it "collects edge and semantic keys honoring scope=all vs project"  , :aggregate_failures do
    client = double("redis-client")
    allow(Redis).to receive(:new).and_return(client)
    allow(client).to receive(:call).and_return(nil)

    # For edges
    allow(client).to receive(:scan).and_return(["0", ["edge:a", "edge:b"]])
    memory = described_class.new(project: project)
    allow(memory).to receive(:load_episode).with("edge:a").and_return({ "project" => project })
    allow(memory).to receive(:load_episode).with("edge:b").and_return({ "project" => "other" })

    project_keys = memory.send(:collect_edge_keys, scope: "project")
    expect(project_keys).to include("edge:a")
    expect(project_keys).not_to include("edge:b")

    all_keys = memory.send(:collect_edge_keys, scope: "all")
    expect(all_keys).to include("edge:a", "edge:b")

    # For semantic keys
    allow(client).to receive(:scan).and_return(["0", ["semantic:1", "semantic:2"]])
    allow(client).to receive(:hgetall).with("semantic:1").and_return({ "project" => project })
    allow(client).to receive(:hgetall).with("semantic:2").and_return({ "project" => "other" })

    sem_project = memory.send(:collect_semantic_keys, scope: "project")
    expect(sem_project).to include("semantic:1")
    expect(sem_project).not_to include("semantic:2")

    sem_all = memory.send(:collect_semantic_keys, scope: "all")
    expect(sem_all).to include("semantic:1", "semantic:2")
  end

  it "delete_recent returns early for zero limit and delete_all merges keys correctly"  , :aggregate_failures do
    client = double("redis-client")
    allow(Redis).to receive(:new).and_return(client)
    allow(client).to receive(:call).and_return(nil)
    memory = described_class.new(project: project)

    res = memory.send(:delete_recent, limit: 0, scope: "project", type: nil, agent: nil, dry_run: true)
    expect(res["deleted_ids"]).to eq([])

    # For delete_all, stub collectors and delete_keys
    episodic = [{ "id" => "1" }, { "id" => "2" }]
    allow(memory).to receive(:collect_episode_records).and_return(episodic)
    allow(memory).to receive(:collect_related_edge_keys).and_return(["edge:1"])
    allow(memory).to receive(:collect_edge_keys).and_return(["edge:all"])
    allow(memory).to receive(:collect_semantic_keys).and_return(["semantic:all"])
    allow(memory).to receive(:delete_keys).and_return({ "deleted_count" => 3 })

    result = memory.send(:delete_all, scope: "project", type: nil, agent: nil, dry_run: false)
    expect(result["mode"]).to eq("all")
    expect(result["deleted_ids"]).to include("1", "2")
  end
end
