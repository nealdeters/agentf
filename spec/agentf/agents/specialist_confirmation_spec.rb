# frozen_string_literal: true

RSpec.describe Agentf::Agents::Specialist do
  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }
  subject(:agent) { described_class.new(memory) }

  before { allow(agent).to receive(:log) }

  it "returns confirmation_required when memory requires confirmation on success" do
    confirmation = Agentf::Memory::RedisMemory::ConfirmationRequired.new("confirm", { reason: "ask_first" })
    allow(memory).to receive(:store_success).and_raise(confirmation)

    res = agent.execute({ "id" => "1", "description" => "Run job", "success" => true })
    expect(res["confirmation_required"]).to be(true)
    expect(res["confirmation_details"]).to eq(confirmation.details)
  end

  it "returns confirmation_required when memory requires confirmation on pitfall" do
    confirmation = Agentf::Memory::RedisMemory::ConfirmationRequired.new("confirm", { reason: "ask_first" })
    allow(memory).to receive(:store_pitfall).and_raise(confirmation)

    res = agent.execute({ "id" => "2", "description" => "Do bad", "success" => false })
    expect(res["confirmation_required"]).to be(true)
    expect(res["confirmation_details"]).to eq(confirmation.details)
  end
end
