# frozen_string_literal: true

RSpec.describe Agentf::Memory::RedisMemory do
  let(:project) { "test-project" }

  subject(:memory) { described_class.new(project: project) }

  describe "low-level helpers" do
    it "parses embeddings from JSON strings and arrays"  , :aggregate_failures do
      expect(memory.send(:parse_embedding, nil)).to eq([])
      expect(memory.send(:parse_embedding, "")).to eq([])
      expect(memory.send(:parse_embedding, "not json")).to eq([])
      expect(memory.send(:parse_embedding, "[1,2,3]")).to eq([1.0, 2.0, 3.0])
      expect(memory.send(:parse_embedding, [4, 5])).to eq([4.0, 5.0])
    end

    it "computes cosine similarity edge cases"  , :aggregate_failures do
      expect(memory.send(:cosine_similarity, [], [])).to eq(0.0)
      expect(memory.send(:cosine_similarity, [1, 2], [1])).to eq(0.0)
      expect(memory.send(:cosine_similarity, [0.0, 0.0], [0.0, 0.0])).to eq(0.0)
      expect(memory.send(:cosine_similarity, [1.0, 0.0], [0.0, 1.0])).to be_within(0.0001).of(0.0)
      expect(memory.send(:cosine_similarity, [1.0, 0.0], [1.0, 0.0])).to be_within(0.0001).of(1.0)
    end

    it "normalizes scope and episode ids"  , :aggregate_failures do
      expect(memory.send(:normalize_scope, "all")).to eq("all")
      expect(memory.send(:normalize_scope, "project")).to eq("project")
      expect(memory.send(:normalize_episode_id, "episodic:abc")).to eq("abc")
      expect(memory.send(:normalize_episode_id, "def")).to eq("def")
    end

    it "extracts metadata slice and escapes tags"  , :aggregate_failures do
      meta = { "intent_kind" => "business", "agent_role" => "PLANNER", "other" => 1 }
      slice = memory.send(:extract_metadata_slice, meta, %w[intent_kind agent_role])
      expect(slice).to eq({ "intent_kind" => "business", "agent_role" => "PLANNER" })

      expect(memory.send(:escape_tag, "a-b{c}")).to include("\\-")
    end

    it "infers division, specialty and capabilities for known roles"  , :aggregate_failures do
      expect(memory.send(:infer_division, Agentf::AgentRoles::PLANNER)).to eq("strategy")
      expect(memory.send(:infer_specialty, Agentf::AgentRoles::ENGINEER)).to eq("implementation")
      caps = memory.send(:infer_capabilities, Agentf::AgentRoles::QA_TESTER)
      expect(caps).to include("test")
    end
  end

  describe "collection and deletion helpers" do
    it "fetches edges without search by delegating to load_episode"  , :aggregate_failures do
      client = double("client")
      allow(client).to receive(:scan).and_return(["0", ["edge:1"]])
      memory.instance_variable_set(:@client, client)

      allow(memory).to receive(:load_episode).with("edge:1").and_return({
        "id" => "edge_1", "source_id" => "node-1", "target_id" => "node-2", "project" => project, "relation" => "rel"
      })

      edges = memory.send(:fetch_edges_without_search, node_id: "node-1", relation_filters: nil, limit: 10)
      expect(edges).to be_an(Array)
      expect(edges.first["id"]).to eq("edge_1")
    end

    it "fetches memories without search and sorts by created_at" do
      client = double("client")
      allow(client).to receive(:scan).and_return(["0", ["episodic:1", "episodic:2"]])
      memory.instance_variable_set(:@client, client)

      now = Time.now.to_i
      allow(memory).to receive(:load_episode).with("episodic:1").and_return({ "id" => "1", "project" => project, "created_at" => now - 10 })
      allow(memory).to receive(:load_episode).with("episodic:2").and_return({ "id" => "2", "project" => project, "created_at" => now })

      results = memory.send(:fetch_memories_without_search, limit: 10)
      expect(results.first["id"]).to eq("2")
    end

    it "delete_keys respects dry_run and actual deletion"  , :aggregate_failures do
      client = double("client")
      memory.instance_variable_set(:@client, client)
      result = memory.send(:delete_keys, ["a", "b"], dry_run: true)
      expect(result["dry_run"]).to be(true)

      allow(client).to receive(:del).with(*["a", "b"]).and_return(2)
      result2 = memory.send(:delete_keys, ["a", "b"], dry_run: false)
      expect(result2["deleted_count"]).to eq(2)
    end
  end

  describe "error helper predicates" do
    it "detects index already exists messages" do
      err = RuntimeError.new("Index already exists")
      expect(memory.send(:index_already_exists?, err)).to be true
    end

    it "detects missing module errors"  , :aggregate_failures do
      e1 = RuntimeError.new("Unknown command 'JSON.SET'")
      e2 = RuntimeError.new("Unknown command 'FT.SEARCH'")
      expect(memory.send(:missing_json_module?, e1)).to be true
      expect(memory.send(:missing_search_module?, e2)).to be true
    end
  end

  describe "traversal helpers" do
    it "traverse_edges aggregates layers and nodes"  , :aggregate_failures do
      # stub fetch_edges_for to return edges that link node1->node2 and node2->node3
      allow(memory).to receive(:fetch_edges_for).and_return([
        { "id" => "e1", "source_id" => "n1", "target_id" => "n2", "project" => project },
        { "id" => "e2", "source_id" => "n2", "target_id" => "n3", "project" => project }
      ])

      result = memory.send(:traverse_edges, seed_ids: ["n1"], relation_filters: nil, depth: 2, limit: 10)
      expect(result["nodes"]).to include("n1", "n2", "n3")
      expect(result["edges"].length).to be >= 1
    end
  end
end
