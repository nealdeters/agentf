# frozen_string_literal: true

require "spec_helper"
require "agentf/mcp/server"
require "json"

RSpec.describe Agentf::MCP::Server do
  let(:explorer) { instance_double(Agentf::Commands::Explorer) }
  let(:reviewer) { instance_double(Agentf::Commands::MemoryReviewer) }
  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }

  let(:env) { {} }

  subject(:mcp) do
    described_class.new(explorer: explorer, reviewer: reviewer, memory: memory, env: env)
  end

  describe "tool registration" do
    it "registers known tools" do
      tools = mcp.server.list_tools
      names = tools.map { |t| t[:name] }

      expect(names).to contain_exactly(*described_class::KNOWN_TOOLS)
    end
  end

  describe "guardrails" do
    it "blocks write tools when writes disabled" do
      server = described_class.new(
        explorer: explorer, reviewer: reviewer, memory: memory,
        env: { "AGENTF_MCP_ALLOW_WRITES" => "false" }
      )

      result = server.server.call_tool("agentf-memory-add-lesson", title: "T", description: "D")
      expect(result).to include("Write tools are disabled")
    end
  end

  describe "agentf-memory-recent" do
    it "calls reviewer.get_recent_memories with default limit"  , :aggregate_failures do
      allow(reviewer).to receive(:get_recent_memories).with(limit: 10).and_return(
        "count" => 1, "memories" => [{ "title" => "Test" }]
      )

      result = mcp.server.call_tool("agentf-memory-recent")
      payload = JSON.parse(result)

      expect(payload["count"]).to eq(1)
      expect(payload["memories"].first["title"]).to eq("Test")
    end
  end

  describe "agentf-memory-search" do
    it "calls reviewer.search with query and limit" do
      allow(reviewer).to receive(:search).with("react", limit: 10).and_return(
        "count" => 2, "memories" => [{ "title" => "React lesson" }, { "title" => "React hooks" }]
      )

      result = mcp.server.call_tool("agentf-memory-search", query: "react")
      payload = JSON.parse(result)

      expect(payload["count"]).to eq(2)
    end
  end

  describe "agentf-memory-episodes" do
    it "calls reviewer.get_episodes with optional outcome" do
      allow(reviewer).to receive(:get_episodes).with(limit: 10, outcome: "negative").and_return(
        "count" => 1, "memories" => [{ "title" => "Deploy failed", "outcome" => "negative" }]
      )

      result = mcp.server.call_tool("agentf-memory-episodes", outcome: "negative")
      payload = JSON.parse(result)

      expect(payload["count"]).to eq(1)
      expect(payload.dig("memories", 0, "outcome")).to eq("negative")
    end
  end

  describe "agentf-memory-intents" do
    it "calls reviewer.get_intents when no kind is provided" do
      allow(reviewer).to receive(:get_intents).with(limit: 10).and_return(
        "count" => 1, "memories" => [{ "title" => "Reliability" }]
      )

      result = mcp.server.call_tool("agentf-memory-intents")
      payload = JSON.parse(result)

      expect(payload["count"]).to eq(1)
      expect(payload.dig("memories", 0, "title")).to eq("Reliability")
    end
  end

  describe "agentf-memory-add-lesson" do
    it "stores a lesson via memory.store_episode"  , :aggregate_failures do
      allow(memory).to receive(:store_episode).with(
        type: "lesson",
        title: "New learning",
        description: "Discovered pattern",
        agent: "PLANNER",
        context: "planning",
        code_snippet: ""
      ).and_return("episode_123")

      result = mcp.server.call_tool(
        "agentf-memory-add-lesson",
        title: "New learning",
        description: "Discovered pattern",
        agent: "PLANNER",
        context: "planning"
      )
      payload = JSON.parse(result)

      expect(payload["id"]).to eq("episode_123")
      expect(payload["type"]).to eq("lesson")
      expect(payload["status"]).to eq("stored")
    end
  end

  describe "agentf-memory-add-playbook" do
    it "stores a playbook via memory.store_playbook"  , :aggregate_failures do
      allow(memory).to receive(:store_playbook).with(
        title: "Release rollout",
        description: "Deploy safely",
        agent: "PLANNER",
        steps: ["deploy canary", "monitor"],
        feature_area: "release"
      ).and_return("episode_456")

      result = mcp.server.call_tool(
        "agentf-memory-add-playbook",
        title: "Release rollout",
        description: "Deploy safely",
        steps: ["deploy canary", "monitor"],
        feature_area: "release"
      )
      payload = JSON.parse(result)

      expect(payload["id"]).to eq("episode_456")
      expect(payload["type"]).to eq("playbook")
    end
  end

  describe "agentf-memory-neighbors" do
    it "calls reviewer.neighbors with keyword arguments" do
      allow(reviewer).to receive(:neighbors).with("episode_1", relation: "related_to", depth: 2, limit: 3).and_return(
        "seed_ids" => ["episode_1"], "count" => 1, "edges" => []
      )

      result = mcp.server.call_tool(
        "agentf-memory-neighbors",
        node_id: "episode_1",
        relation: "related_to",
        depth: 2,
        limit: 3
      )
      payload = JSON.parse(result)

      expect(payload["count"]).to eq(1)
    end
  end
end
