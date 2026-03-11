# frozen_string_literal: true

require 'ostruct'

RSpec.describe Agentf::Agents::Designer do
  let(:memory) { instance_double(Agentf::Memory::RedisMemory) }
  let(:commands) { instance_double(Agentf::Commands::Designer) }
  let(:spec) { OpenStruct.new(name: "GeneratedComponent", framework: "react", code: "<div/>") }

  subject(:agent) { described_class.new(memory, commands: commands) }

  before do
    allow(agent).to receive(:log)
    allow(commands).to receive(:generate_component).and_return(spec)
  end

  it "returns confirmation_required when memory requires confirmation" do
    confirmation = Agentf::Memory::RedisMemory::ConfirmationRequired.new("confirm", { reason: "ask_first" })
    allow(memory).to receive(:store_success).and_raise(confirmation)

    res = agent.implement_design("Create card")
    expect(res["confirmation_required"]).to be(true)
    expect(res["confirmation_details"]).to eq(confirmation.details)
  end
end
