# frozen_string_literal: true

require "spec_helper"

RSpec.describe Agentf::Memory::RedisMemory do
  let(:project) { "test-project" }

  it "loads episodes via JSON.GET and falls back to GET when RedisJSON missing"  , :aggregate_failures do
    client = double("redis-client")
    allow(Redis).to receive(:new).and_return(client)

    # Default allow any call during initialization to succeed unless specifically stubbed
    allow(client).to receive(:call).and_return(nil)
    # First, simulate JSON.GET succeeding
    allow(client).to receive(:call).with("JSON.GET", "episodic:1", ".").and_return('{"id":"1","project":"test-project"}')
    memory = described_class.new(project: project)

    # Make @json_supported true to force JSON.GET path
    memory.instance_variable_set(:@json_supported, true)
    allow(client).to receive(:call).with("JSON.GET", "episodic:1", ".")
      .and_return('{"id":"1","project":"test-project"}')

    result = memory.send(:load_episode, "episodic:1")
    expect(result).to be_a(Hash)
    expect(result["id"]).to eq("1")

    # Now simulate JSON.GET raising unknown command; client.get should be used
    allow(client).to receive(:call).with("JSON.GET", "episodic:2", ".").and_raise(Redis::CommandError.new("Unknown command 'JSON.GET'"))
    allow(client).to receive(:get).with("episodic:2").and_return('{"id":"2","project":"test-project"}')
    memory.instance_variable_set(:@json_supported, true)
    res2 = memory.send(:load_episode, "episodic:2")
    expect(res2).to be_a(Hash)
    expect(res2["id"]).to eq("2")

    # And when the stored payload is invalid JSON, load_episode returns nil
    allow(client).to receive(:get).with("episodic:3").and_return('not-json')
    memory.instance_variable_set(:@json_supported, false)
    expect(memory.send(:load_episode, "episodic:3")).to be_nil
  end

  it "parses FT.SEARCH results in search_episodic and skips invalid JSON" do
    client = double("redis-client")
    allow(Redis).to receive(:new).and_return(client)

    # Default allow any call during initialization to succeed unless specifically stubbed
    allow(client).to receive(:call).and_return(nil)
    # Build a fake FT.SEARCH response: [total, id, itemArray]
    valid_item = ["$", '{"id":"e1","project":"test-project"}']
    invalid_item = ["$", 'not-json']
    results = [2, "episodic:1", valid_item, "episodic:2", invalid_item]

    # Return results only for the FT.SEARCH episodic call
    allow(client).to receive(:call) do |cmd, *args|
      if cmd == "FT.SEARCH" && args[0] == Agentf::Memory::RedisMemory::EPISODIC_INDEX
        results
      else
        nil
      end
    end
    memory = described_class.new(project: project)

    memories = memory.send(:search_episodic, query: "@project:{test-project}", limit: 10)
    expect(memories).to be_an(Array)
    expect(memories.length).to eq(1)
    expect(memories.first["id"]).to eq("e1")
  end

  it "parses FT.SEARCH results for JSON index via search_json_index" do
    client = double("redis-client")
    allow(Redis).to receive(:new).and_return(client)

    # Default allow any call during initialization to succeed unless specifically stubbed
    allow(client).to receive(:call).and_return(nil)
    rec = ["$", '{"id":"edge1","source_id":"n1","target_id":"n2","project":"test-project"}']
    results = [1, "edge:edge1", rec]
    allow(client).to receive(:call) do |cmd, *args|
      if cmd == "FT.SEARCH" && args[0] == Agentf::Memory::RedisMemory::EDGE_INDEX
        results
      else
        nil
      end
    end

    memory = described_class.new(project: project)
    records = memory.send(:search_json_index, index: Agentf::Memory::RedisMemory::EDGE_INDEX, query: "@project:{test-project}", limit: 5)
    expect(records.length).to eq(1)
    expect(records.first["source_id"]).to eq("n1")
  end

  it "parses FT.SEARCH vector results including returned distance" , :aggregate_failures do
    results = [1, "episodic:1", ["$", '{"id":"e1","project":"test-project","type":"lesson"}', "vector_distance", "0.123"]]

    memory = described_class.new(project: project)
    records = memory.send(:parse_search_results, results)

    expect(records.length).to eq(1)
    expect(records.first["id"]).to eq("e1")
    expect(records.first["vector_distance"]).to eq("0.123")
  end

  it "uses native vector search when supported and reranks returned candidates" , :aggregate_failures do
    client = double("redis-client")
    allow(Redis).to receive(:new).and_return(client)
    allow(client).to receive(:call).and_return(nil)

    provider = instance_double(Agentf::EmbeddingProvider, embed: [1.0, 0.0])
    memory = described_class.new(project: project, embedding_provider: provider)
    memory.instance_variable_set(:@vector_search_supported, true)
    allow(memory).to receive(:vector_search_supported?).and_return(true)
    allow(memory).to receive(:vector_search_episodes).and_return([
      { "id" => "e1", "project" => project, "type" => "lesson", "title" => "Redis caching", "description" => "Use Redis for sessions", "embedding" => [1.0, 0.0], "vector_distance" => 0.01 },
      { "id" => "e2", "project" => project, "type" => "lesson", "title" => "SQL indexing", "description" => "Add indexes", "embedding" => [0.0, 1.0], "vector_distance" => 0.65 }
    ])

    result = memory.search_memories(query: "redis sessions", limit: 1)

    expect(result.length).to eq(1)
    expect(result.first["id"]).to eq("e1")
    expect(result.first["score"]).to be > 0.7
  end

  it "falls back from native vector search when query support is unavailable" , :aggregate_failures do
    client = double("redis-client")
    allow(Redis).to receive(:new).and_return(client)
    allow(client).to receive(:call).and_return(nil)

    provider = instance_double(Agentf::EmbeddingProvider, embed: [1.0, 0.0])
    memory = described_class.new(project: project, embedding_provider: provider)
    memory.instance_variable_set(:@vector_search_supported, true)
    allow(memory).to receive(:collect_episode_records).with(scope: "project", type: nil, agent: nil).and_return([
      { "id" => "fallback-1", "project" => project, "type" => "lesson", "title" => "Redis caching", "description" => "Use Redis for sessions", "embedding" => [1.0, 0.0] },
      { "id" => "fallback-2", "project" => project, "type" => "lesson", "title" => "Queues", "description" => "Background jobs", "embedding" => [0.0, 1.0] }
    ])
    allow(memory).to receive(:vector_search_supported?).and_return(true)
    allow(client).to receive(:call).with(
      "FT.SEARCH",
      Agentf::Memory::RedisMemory::EPISODIC_INDEX,
      /^@project:\{test\\-project\}=>\[KNN 10 @embedding \$query_vector AS vector_distance\]$/,
      "PARAMS", "2", "query_vector", kind_of(String),
      "SORTBY", "vector_distance", "ASC",
      "RETURN", "2", "$", "vector_distance",
      "DIALECT", "2",
      "LIMIT", "0", "10"
    ).and_raise(Redis::CommandError.new("Syntax error near KNN"))

    result = memory.search_memories(query: "redis sessions", limit: 1)

    expect(result.first["id"]).to eq("fallback-1")
    expect(memory.instance_variable_get(:@vector_search_supported)).to be false
  end

  it "finds similar tasks using cosine similarity and filters by project"  , :aggregate_failures do
    client = double("redis-client")
    allow(Redis).to receive(:new).and_return(client)

    # Default allow any call during initialization to succeed unless specifically stubbed
    allow(client).to receive(:call).and_return(nil)
    # scan returns one semantic key
    allow(client).to receive(:scan).and_return(["0", ["semantic:task1"]])
    allow(client).to receive(:hgetall).with("semantic:task1").and_return({
      "id" => "task1",
      "project" => project,
      "embedding" => JSON.generate([1.0, 0.0])
    })

    memory = described_class.new(project: project)
    res = memory.find_similar_tasks(query_embedding: [1.0, 0.0], limit: 5)
    expect(res).to be_an(Array)
    expect(res.first["id"]).to eq("task1")
    expect(res.first).to have_key("score")
  end
end
