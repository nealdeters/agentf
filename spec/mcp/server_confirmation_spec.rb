# frozen_string_literal: true

require "spec_helper"
require "agentf/mcp/server"

RSpec.describe Agentf::MCP::Server do
  let(:explorer) { instance_double(Agentf::Commands::Explorer) }
  let(:reviewer) { instance_double(Agentf::Commands::MemoryReviewer) }
  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }

  subject(:mcp) { described_class.new(explorer: explorer, reviewer: reviewer, memory: memory, env: {}) }

  it "returns confirmation metadata for memory write tools"  , :aggregate_failures do
    confirmation = Agentf::Memory::RedisMemory::ConfirmationRequired.new("confirm", { reason: "ask_first" })
    allow(memory).to receive(:store_episode).and_raise(confirmation)

    result = JSON.parse(mcp.server.call_tool("agentf-memory-add-lesson", title: "T", description: "D"))

    expect(result["confirmation_required"]).to be(true)
    expect(result["confirmed_write_token"]).to eq("confirmed")
    expect(result["confirmation_prompt"]).to include("Ask the user")
  end
end
