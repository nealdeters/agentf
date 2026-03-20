# frozen_string_literal: true

RSpec.describe Agentf::Agents::Security do
  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }
  let(:commands) { instance_double(Agentf::Commands::SecurityScanner) }
  subject(:agent) { described_class.new(memory, commands: commands) }

  before { allow(agent).to receive(:log) }

  it "returns confirmation_required when storing success is blocked"  , :aggregate_failures do
    allow(commands).to receive(:scan).and_return({ "issues" => [] })
    confirmation = Agentf::Memory::RedisMemory::ConfirmationRequired.new("confirm", { reason: "ask_first" })
    allow(memory).to receive(:store_episode).and_raise(confirmation)

    res = agent.assess(task: "Check" )
    expect(res["confirmation_required"]).to be(true)
    expect(res["confirmation_details"]).to eq(confirmation.details)
  end

  it "returns confirmation_required when storing pitfall is blocked"  , :aggregate_failures do
    allow(commands).to receive(:scan).and_return({ "issues" => [{ "issue" => "secret" }] })
    confirmation = Agentf::Memory::RedisMemory::ConfirmationRequired.new("confirm", { reason: "ask_first" })
    allow(memory).to receive(:store_episode).and_raise(confirmation)

    res = agent.assess(task: "Check")
    expect(res["confirmation_required"]).to be(true)
    expect(res["confirmation_details"]).to eq(confirmation.details)
  end
end
