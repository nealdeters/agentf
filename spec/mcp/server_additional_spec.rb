# frozen_string_literal: true

require "spec_helper"
require "agentf/mcp/server"

RSpec.describe Agentf::MCP::Server do
  let(:explorer) { instance_double(Agentf::Commands::Explorer) }
  let(:reviewer) { instance_double(Agentf::Commands::MemoryReviewer) }
  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }
  subject(:mcp) { described_class.new(explorer: explorer, reviewer: reviewer, memory: memory, env: {}) }

  describe "guard helper behavior" do
    it "asserts tool allowed"  , :aggregate_failures do
      server = described_class.new(explorer: explorer, reviewer: reviewer, memory: memory, env: { "AGENTF_MCP_ALLOWED_TOOLS" => "agentf-code-glob" })
      expect(server.guardrails[:allowed_tools]).to eq(Set.new(["agentf-code-glob"]))
      allow(explorer).to receive(:glob).with("**/*", file_types: nil).and_return(["a.rb"])
      res = server.server.call_tool("agentf-code-glob", pattern: "**/*")
      payload = JSON.parse(res)
      expect(payload["pattern"]).to eq("**/*")
      expect(payload["matches"]).to eq(["a.rb"])
    end

    it "parse_boolean_env recognizes common true/false values" do
      s = described_class.new(explorer: explorer, reviewer: reviewer, memory: memory, env: { "AGENTF_MCP_ALLOW_WRITES" => "no" })
      expect(s.guardrails[:allow_writes]).to be false
    end
  end

  describe "runtime adapter" do
    it "can build a runtime-capable registry adapter even without the old DSL" do
      expect(mcp.server).to respond_to(:list_tools)
      expect(mcp.server).to respond_to(:run)
      expect(mcp.server.list_tools).not_to be_empty
    end

    it "builds runtime MCP responses with structured text hashes" do
      adapter = mcp.server
      runtime_server = adapter.send(:build_runtime_server)
      response = runtime_server.send(:call_tool, { name: "agentf-memory-recent", arguments: { limit: 1 } })

      expect(response[:content]).to be_an(Array)
      expect(response[:content].first).to be_a(Hash)
      expect(response[:content].first[:type]).to eq("text")
    end
  end
end
